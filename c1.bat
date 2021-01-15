@echo off
echo Compiling kernel...
IF NOT EXIST build (
	mkdir build
)
gcc kernel.c -m32 -c -O3 -o ./build/kernel.obj