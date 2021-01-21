@echo off
echo Compiling kernel...
IF NOT EXIST build (
	mkdir build
)
g++ kernel.c -m32 -c -O3 -o ./build/kernel.obj -fpermissive