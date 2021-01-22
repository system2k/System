@echo off
echo Compiling kernel...
IF NOT EXIST build (
	mkdir build
)
g++ kernel.cpp -m32 -c -O3 -o ./build/kernel.obj