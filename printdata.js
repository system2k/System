var fs = require("fs");
var child_process = require("child_process");

var codeSection = ".text";
var dataSection = ".data";
var readonlyDataSection = ".rdata";

// paths
var binCodePath = "./build/exec_code.bin";
var binDataPath = "./build/exec_data.bin";
var binRdataPath = "./build/exec_rdata.bin";
var objPath = "./build/kernel.obj";
var relocDataPath = "./build/reloc.bin";

// take bytecode from .text section, and data from .rdata/.data
child_process.execSync("objcopy -O binary -j " + codeSection + " " + objPath + " " + binCodePath);
child_process.execSync("objcopy -O binary -j " + dataSection + " " + objPath + " " + binDataPath);
child_process.execSync("objcopy -O binary -j " + readonlyDataSection + " " + objPath + " " + binRdataPath);


var relocBufferSize = 1; // includes null terminator
var enumReloc = {
	term: 0,
	data: 1,
	rdata: 2,
	bss: 3,
	glob: 4,
	bssSize: 5,
	globVarSize: 6
};
var relocData = [];


var relocation = child_process.execSync("objdump -r " + objPath);
relocation = parseRelocationDmp(relocation.toString("utf8"));

var binCode = fs.readFileSync(binCodePath);
var binData = fs.readFileSync(binDataPath);
var binRdata = fs.readFileSync(binRdataPath);

var dataStart = 7000000;
var dataStartBss = 8000000;
var rdataStart = 9000000;
var globStart = 7500000; // test only - these seem to be relocation records for global variables

function parseRelocationDmp(data) {
	data = data.replace(/\r\n/g, "\n");
	data = data.split("\n");
	var currentSection = null;
	var records = {};
	var globVarStart = 0;
	var globVarList = {};
	for(var i = 0; i < data.length; i++) {
		var row = data[i];
		var magicLabelStart = "RELOCATION RECORDS FOR [";
		var magicLabelEnd = "]:";
		if(row.startsWith(magicLabelStart) && row.endsWith(magicLabelEnd)) {
			currentSection = row.slice(magicLabelStart.length, -magicLabelEnd.length);
			if(!records[currentSection]) {
				records[currentSection] = {
					data: [],
					rdata: [],
					bss: [],
					glob: []
				};
			}
			continue;
		}
		if(currentSection) {
			var cols = row.split(/[\s]+/g);
			var addr = cols[0];
			var type = cols[1];
			var val = cols[2];
			if(type == "dir32") {
				addr = parseInt(addr, 16);
				if(val == ".bss") {
					records[currentSection].bss.push(addr);
				} else if(val == ".rdata") {
					records[currentSection].rdata.push(addr);
				} else if(val == ".data") {
					records[currentSection].data.push(addr);
				} else {
					if(val.indexOf("-") > -1) {
						var globParts = val.split("-");
						var globName = globParts[0];
						var globSize = parseInt(globParts[1].slice(2), 16); // remove 0x
						if(globVarList[globName] === void 0) {
							globVarList[globName] = globVarStart;
							globVarStart += globSize;
						}
						records[currentSection].glob.push([ // share same buffer for all globals
							addr, globVarList[globName]
						]);
					} else {
						throw "Unknown data type";
					}
				}
			}
		}
	}
	console.log("Globals:", globVarList);
	if(globVarStart) {
		console.log("Size of globals buffer:", globVarStart);
		relocData.push([enumReloc.globVarSize, globVarStart]);
		relocBufferSize += 1 + 4;
	}
	return records;
}

var textReloc = relocation[".text"];

if(textReloc) {
	var relocation_data = textReloc.data;
	var relocation_rdata = textReloc.rdata;
	var relocation_bss = textReloc.bss;
	var relocation_glob = textReloc.glob;
	
	var bssMaxPtr = -1;

	for(var i = 0; i < relocation_data.length; i++) {
		var reloc = relocation_data[i];
		relocData.push([enumReloc.data, reloc]);
		relocBufferSize += 1 + 4;
	}
	for(var i = 0; i < relocation_bss.length; i++) {
		var reloc = relocation_bss[i];
		var ptr = binCode.readUInt32LE(reloc);
		if(ptr > bssMaxPtr) bssMaxPtr = ptr;
		relocData.push([enumReloc.bss, reloc]);
		relocBufferSize += 1 + 4;
	}
	for(var i = 0; i < relocation_rdata.length; i++) {
		var reloc = relocation_rdata[i];
		relocData.push([enumReloc.rdata, reloc]);
		relocBufferSize += 1 + 4;
	}
	for(var i = 0; i < relocation_glob.length; i++) {
		var reloc = relocation_glob[i];
		var rel_ptr = reloc[0];
		var rel_add = reloc[1];
		relocData.push([enumReloc.glob, rel_ptr, rel_add]);
		relocBufferSize += 1 + 4 + 4;
	}
	if(bssMaxPtr > -1) {
		// 4 = size of 32bit val
		var bssSize = bssMaxPtr + 4;
		if(bssSize > 100000) throw "Warning: BSS buffer is very large. Retrieved size of " + bssSize;
		console.log("Size of BSS buffer:", bssSize);
		relocData.push([enumReloc.bssSize, bssSize]);
		relocBufferSize += 1 + 4;
	}
}
console.log("Total size of relocation buffer:", relocBufferSize);
var relocBuffer = Buffer.alloc(relocBufferSize);
var relocBufferPtr = 0;
for(var i = 0; i < relocData.length; i++) {
	var type = relocData[i][0];
	var argA = relocData[i][1];
	var argB = relocData[i][2];
	relocBuffer[relocBufferPtr++] = type;
	relocBuffer.writeUInt32LE(argA, relocBufferPtr);
	relocBufferPtr += 4;
	if(type == enumReloc.glob) {
		relocBuffer.writeUInt32LE(argB, relocBufferPtr);
		relocBufferPtr += 4;
	}
}
fs.writeFileSync(relocDataPath, relocBuffer);

var symData = child_process.execSync("nm " + objPath + " -C").toString("utf8");
symData = symData.replace(/\r\n/g, "\n").split("\n");
var symLocated = false;
var symStart = 0;
for(var i = 0; i < symData.length; i++) {
	var sym = symData[i];
	sym = sym.split(" ");
	if(sym[1] == "T" && sym[2] == "main") {
		var symStartHex = parseInt(sym[0], 16).toString(16).padStart(2, 0).toUpperCase();
		symStart = parseInt(sym[0], 16);
		console.log("main() starting point: 0x" + symStartHex);
		symLocated = true;
		break;
	}
}
if(!symLocated) {
	console.log("Did not locate main() symbol. Assuming location 0.");
}

// prepend jump-ahead instruction if main function starts later
var jmpInstLength = 5;
var jmpMain = Buffer.alloc(jmpInstLength);
jmpMain[0] = 0xE9;
jmpMain.writeUInt32LE(symStart, 1);
binCode = Buffer.concat([jmpMain, binCode]);
fs.writeFileSync(binCodePath, binCode);