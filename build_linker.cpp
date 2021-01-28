/*
	Process relocations
*/

#include <iostream>
#include <stdio.h>
#include <string>
#include <vector>

uint8_t* readFile(const char path[]) {
	FILE *fp = fopen(path, "rb"); // readonly binary
	fseek(fp, 0L, SEEK_END);
	long fileSize = ftell(fp);
	uint8_t* data = new uint8_t[fileSize];
	fseek(fp, 0L, SEEK_SET);
	int len = fread(data, 1, fileSize, fp);
	if(len != fileSize) {
		std::cout << "Warning: did not read full file\n";
	}
	if(ferror(fp) != 0) {
		std::cout << "readError\n";
	}
	fclose(fp);
	return data;
}

int writeFile(const char path[], uint8_t* data, int len) {
	FILE *fp = fopen(path, "wb"); // write binary
	int writeLen = fwrite(data, 1, len, fp);
	if(ferror(fp) != 0) {
		std::cout << "Error while writing file\n";
	}
	fclose(fp);
	return writeLen;
}

std::string execProc(const char cmd[]) {
	char buf[512];
	std::string res = "";
	FILE* pipe = popen(cmd, "r");
	if(!pipe) {
		std::cout << "Pipe error\n";
	}
	while(!feof(pipe)) {
		if(fgets(buf, 512, pipe) != NULL) {
			res += buf;
		}
	}
	pclose(pipe);
	return res;
}

int strlen(const char str[]) {
	int size = 0;
	int i = 0;
	while(str[i++]) {
		size++;
	}
	return size;
}

bool checkStr(int pos, const char* buf, const char substr[]) {
	int sp = 0;
	while(substr[sp]) {
		if(buf[pos++] != substr[sp++]) return false;
	}
	return true;
}

int locateChar(int pos, const char* buf, int bufLen, char chr) {
	while(true) {
		if(pos >= bufLen) return -1;
		if(buf[pos] == chr) return pos;
		pos++;
	}
	return -1;
}

int locateExcludeChar(int pos, const char* buf, int bufLen, char chr) {
	while(true) {
		if(pos >= bufLen) return -1;
		if(buf[pos] != chr) return pos;
		pos++;
	}
	return -1;
}

int parseHexDigit(char chr) {
	if('0' <= chr && chr <= '9') return chr - '0';
	if('a' <= chr && chr <= 'f') return chr - 'a' + 10;
	if('A' <= chr && chr <= 'F') return chr - 'A' + 10;
	return 0;
}

uint32_t parseHex(int start, int end, const char* buf) {
	int len = end - start + 1;
	uint32_t res = 0;
	uint32_t mul = 1;
	for(int i = 0; i < len; i++) {
		int num = parseHexDigit(buf[end - i]);
		res += mul * num;
		mul *= 16;
	}
	return res;
}

std::vector<std::vector<uint32_t>> parseRelocDump(const char section[], const char* dmp, int dmpLen) {
	const char relocMarker[] = "RELOCATION RECORDS FOR";
	const char sectMarker[] = ".text";
	int i = locateExcludeChar(0, dmp, dmpLen, '\n');
	int globVarStart = 0;
	
	std::vector<uint32_t> miscInfo; // glob_buffer_size
	// relocation pointers
	std::vector<uint32_t> bssList;
	std::vector<uint32_t> rdataList;
	std::vector<uint32_t> dataList;
	std::vector<uint32_t> textList;
	
	// all globals will share one global-var buffer
	std::vector<uint32_t> globVarList;
	std::vector<uint32_t> globVarOffset; // offset to be added to above relocation
	
	bool sectionFound = false;
	while(true) {
		int start = locateExcludeChar(i, dmp, dmpLen, '\n');
		if(start == -1) break;
		int end = locateChar(start + 1, dmp, dmpLen, '\n');
		if(end == -1) end = dmpLen;
		int lineSize = end - start;
		
		if(checkStr(start, dmp, relocMarker)) {
			int sectionName = locateChar(start, dmp, dmpLen, '[');
			sectionName++;
			if(checkStr(sectionName, dmp, sectMarker)) {
				sectionFound = true;
			} else {
				sectionFound = false;
			}
			i = end;
			if(i >= dmpLen) break;
			continue;
		}
		
		if(sectionFound) {
			if(checkStr(start, dmp, "OFFSET")) {
				i = end;
				if(i >= dmpLen) break;
				continue;
			}
			int hexStart = start;
			int hexEnd = locateChar(hexStart, dmp, dmpLen, ' ');
			int hexLen = hexEnd - hexStart + 1;
			
			int typeStart = locateExcludeChar(hexEnd, dmp, dmpLen, ' ');
			int typeEnd = locateChar(typeStart, dmp, dmpLen, ' ');
			int typeLen = typeEnd - typeStart + 1;
			
			int sectionStart = locateExcludeChar(typeEnd, dmp, dmpLen, ' ');
			int sectionEnd = end - 1;
			int sectionLen = sectionEnd - sectionStart + 1;
			typeEnd--;
			hexEnd--;
			
			uint32_t relocVal = parseHex(hexStart, hexEnd, dmp);
			
			if(!checkStr(typeStart, dmp, "dir32")) {
				i = end;
				if(i >= dmpLen) break;
				continue;
			}
			
			if(checkStr(sectionStart, dmp, ".bss")) {
				bssList.push_back(relocVal);
			} else if(checkStr(sectionStart, dmp, ".rdata")) {
				rdataList.push_back(relocVal);
			} else if(checkStr(sectionStart, dmp, ".data")) {
				dataList.push_back(relocVal);
			} else if(checkStr(sectionStart, dmp, ".text")) {
				textList.push_back(relocVal);
			} else {
				int chk = locateChar(sectionStart, dmp, dmpLen, '-');
				if(chk != -1 && sectionStart <= chk && chk <= sectionEnd) {
					uint32_t globSize = parseHex(sectionStart, chk - 1, dmp);
					int globStart = globVarStart;
					globVarStart += globSize;
					globVarList.push_back(relocVal);
					globVarOffset.push_back(globStart);
					
				} else {
					std::cout << "Unknown data type";
				}
			}
		}
		
		i = end;
		if(i >= dmpLen) break;
	}
	miscInfo.push_back(globVarStart);
	
	std::vector<std::vector<uint32_t>> vectorList;
	vectorList.push_back(miscInfo); // 0
	vectorList.push_back(bssList); // 1
	vectorList.push_back(rdataList); // 2
	vectorList.push_back(dataList); // 3
	vectorList.push_back(textList); // 4
	vectorList.push_back(globVarList); // 5
	vectorList.push_back(globVarOffset); // 6
	return vectorList;
}

uint32_t getEntryOffset(const char* dmp, int dmpLen) {
	const char entrySearch[] = "KernelMain(";
	int i = locateExcludeChar(0, dmp, dmpLen, '\n');
	uint32_t entry = 0;
	bool entryFound = false;
	while(true) {
		int start = locateExcludeChar(i, dmp, dmpLen, '\n');
		if(start == -1) break;
		int end = locateChar(start + 1, dmp, dmpLen, '\n');
		if(end == -1) end = dmpLen;
		int lineSize = end - start;
		
		int hexStart = start;
		int hexEnd = hexStart + 7;
		uint32_t offsetValue = parseHex(hexStart, hexEnd, dmp);
		char type = dmp[start + 9];
		int funcStart = start + 11;
		int funcEnd = end;
		
		if(type == 'T' && checkStr(funcStart, dmp, entrySearch)) {
			entry = offsetValue;
			entryFound = true;
		}
		if(type == 'U') {
			std::cout << "***WARNING***: Detected missing function: ";
			for(int x = funcStart; x <= funcEnd; x++) {
				std::cout << dmp[x];
			}
			std::cout << "\n";
		}
		
		i = end;
		if(i >= dmpLen) break;
	}
	if(!entryFound) {
		std::cout << "Entry not found, assuming offset 0";
	}
	return entry;
}

void setUint32LE(uint8_t* buf, int pos, uint32_t value) {
	buf[pos++] = value & 0xFF;
	buf[pos++] = value >> 8 & 0xFF;
	buf[pos++] = value >> 16 & 0xFF;
	buf[pos++] = value >> 24 & 0xFF;
}

uint32_t getUint32LE(uint8_t* buf, int pos) {
	return ((uint32_t)(buf[pos])) |
			((uint32_t)(buf[pos + 1]) << 8) |
			((uint32_t)(buf[pos + 2]) << 16) |
			((uint32_t)(buf[pos + 3]) << 24);
}

int main(int argc, char* argv[]) {
	int jmpInstLength = 5;
	
	enum reloc {
		e_term = 0,
		e_data = 1,
		e_rdata = 2,
		e_bss = 3,
		e_glob = 4,
		e_text = 5,
		e_bssSize = 6,
		e_globVarSize = 7,
		e_entry = 8
	};
	
	const char codeSection[] = ".text";
	const char dataSection[] = ".data";
	const char readonlyDataSection[] = ".rdata";

	const char binCodePath[] = "./build/exec_code.bin";
	const char binDataPath[] = "./build/exec_data.bin";
	const char binRdataPath[] = "./build/exec_rdata.bin";
	const char objPath[] = "./build/kernel.obj";
	const char relocDataPath[] = "./build/reloc.bin";
	
	std::cout << "Extracting sections...\n";
	std::string objCode = std::string("objcopy -O binary -j ") + codeSection + " " + objPath + " " + binCodePath;
	std::string objData = std::string("objcopy -O binary -j ") + dataSection + " " + objPath + " " + binDataPath;
	std::string objRdata = std::string("objcopy -O binary -j ") + readonlyDataSection + " " + objPath + " " + binRdataPath;
	
	execProc(objCode.c_str());
	execProc(objData.c_str());
	execProc(objRdata.c_str());
	
	std::string relocObj = std::string("objdump -r ") + objPath;
	std::string relocDataText = execProc(relocObj.c_str());
	
	std::vector<std::vector<uint32_t>> relocData = parseRelocDump(".text", relocDataText.c_str(), relocDataText.length());
	std::vector<uint32_t> miscInfo = relocData.at(0);
	std::vector<uint32_t> bssList = relocData.at(1);
	std::vector<uint32_t> rdataList = relocData.at(2);
	std::vector<uint32_t> dataList = relocData.at(3);
	std::vector<uint32_t> textList = relocData.at(4);
	std::vector<uint32_t> globVarList = relocData.at(5);
	std::vector<uint32_t> globVarOffset = relocData.at(6);
	
	int relocBufferSize = 1; // with null terminator
	relocBufferSize += bssList.size() * (1 + 4);
	relocBufferSize += rdataList.size() * (1 + 4);
	relocBufferSize += dataList.size() * (1 + 4);
	relocBufferSize += textList.size() * (1 + 4);
	relocBufferSize += globVarList.size() * (1 + 4 + 4);
	relocBufferSize += miscInfo.size() * (1 + 4);
	relocBufferSize += (1 + 4); // entry point

	uint8_t* codeData = readFile(binCodePath);
	int bssMaxPtr = -1;
	
	// get size of bss buffer
	for(int i = 0; i < bssList.size(); i++) {
		int reloc = bssList[i];
		int ptr = getUint32LE(codeData, reloc);
		if(ptr > bssMaxPtr) {
			bssMaxPtr = ptr;
		}
	}
	if(bssMaxPtr > -1) {
		relocBufferSize += 1 + 4;
	}
	
	uint8_t* relocBuffer = new uint8_t[relocBufferSize]();
	int relocBufferPtr = 0;
	
	uint32_t globBufSize = miscInfo.at(0);
	relocBuffer[relocBufferPtr++] = e_globVarSize;
	setUint32LE(relocBuffer, relocBufferPtr, globBufSize);
	relocBufferPtr += 4;
	
	if(bssMaxPtr > -1) {
		bssMaxPtr += 4;
		relocBuffer[relocBufferPtr++] = e_bssSize;
		setUint32LE(relocBuffer, relocBufferPtr, bssMaxPtr);
		relocBufferPtr += 4;
	}
	
	for(int x = 0; x < bssList.size(); x++) {
		uint32_t reloc = bssList[x];
		relocBuffer[relocBufferPtr++] = e_bss;
		setUint32LE(relocBuffer, relocBufferPtr, reloc);
		relocBufferPtr += 4;
	}
	for(int x = 0; x < rdataList.size(); x++) {
		uint32_t reloc = rdataList[x];
		relocBuffer[relocBufferPtr++] = e_rdata;
		setUint32LE(relocBuffer, relocBufferPtr, reloc);
		relocBufferPtr += 4;
	}
	for(int x = 0; x < dataList.size(); x++) {
		uint32_t reloc = dataList[x];
		relocBuffer[relocBufferPtr++] = e_data;
		setUint32LE(relocBuffer, relocBufferPtr, reloc);
		relocBufferPtr += 4;
	}
	for(int x = 0; x < textList.size(); x++) {
		uint32_t reloc = textList[x];
		relocBuffer[relocBufferPtr++] = e_text;
		setUint32LE(relocBuffer, relocBufferPtr, reloc);
		relocBufferPtr += 4;
	}
	
	for(int x = 0; x < globVarList.size(); x++) {
		uint32_t reloc = globVarList[x];
		uint32_t offset = globVarOffset[x];
		relocBuffer[relocBufferPtr++] = e_glob;
		setUint32LE(relocBuffer, relocBufferPtr, reloc);
		relocBufferPtr += 4;
		setUint32LE(relocBuffer, relocBufferPtr, offset);
		relocBufferPtr += 4;
	}
	
	std::string symbolData = std::string("nm ") + objPath + " -C";
	std::string symbolDataText = execProc(symbolData.c_str());
	
	uint32_t entry = getEntryOffset(symbolDataText.c_str(), symbolDataText.length());

	relocBuffer[relocBufferPtr++] = e_entry;
	setUint32LE(relocBuffer, relocBufferPtr, entry);
	relocBufferPtr += 4;
	
	if(relocBufferSize > 10000000) {
		std::cout << "ERROR: Reloc buffer too large (>1000000).";
		return 0;
	}
	writeFile(relocDataPath, relocBuffer, relocBufferSize);

	std::cout << "Relocation file has been written.\n";
	std::cout << "Using entry point " << entry << " for kernel.\n";

	return 0;
}