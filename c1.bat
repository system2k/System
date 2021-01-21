@echo off
echo Compiling kernel...
IF NOT EXIST build (
	mkdir build
)
gcc kernel.c -m32 -c -O1 -o ./build/kernel.obj