#include <iostream>
#include <stdio.h>
#include <string>

// g++ build_linker.cpp -o build/link.exe

uint8_t* readFile(const char path[]) {
	FILE *fp = fopen(path, "r");
	fseek(fp, 0L, SEEK_END);
	long fileSize = ftell(fp);
	uint8_t* data = new uint8_t[fileSize];
	fseek(fp, 0L, SEEK_SET);
	int len = fread(data, 1, fileSize, fp);
	if(ferror(fp) != 0) {
		std::cout << "readError\n";
	}
	fclose(fp);
	return data;
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

uint8_t* parseRelocDump(const char* dmp, int dmpLen) {
	const char seekLine[] = "RELOCATION RECORDS FOR [";
	int seekPos = 0;
	for(int i = 0; i < dmpLen; i++) {
		char c = dmp[i];
		if(c == seekLine[seekPos]) {
			seekPos++;
		} else {
			seekPos = 0;
		}
		if(seekPos + 1 >= sizeof(seekLine)) {
			std::cout << "LOCATED LINE\n";
			seekPos = 0;
		}
	}
}

int main(int argc, char* argv[]) {
	enum reloc {
		term = 0,
		data = 1,
		rdata = 2,
		bss = 3,
		glob = 4,
		text = 5,
		bssSize = 6,
		globVarSize = 7
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
	
	/*system(objCode.c_str());
	system(objData.c_str());
	system(objRdata.c_str());*/
	
	std::string relocObj = std::string("objdump -r ") + objPath;
	std::string relocDataText = execProc(relocObj.c_str());
	uint8_t* relocData = parseRelocDump(relocDataText.c_str(), relocDataText.length());


	//uint8_t* codeData = readFile("build/exec_code.bin");
	//std::cout << (int)codeData[0] << "\n";

	


	return 0;
}