@echo off
echo [linker] Processing compilation output and resolving relocations...
IF NOT EXIST link.exe (
echo Compiling linker...
g++ build_linker.cpp -o link.exe
)
echo Relocating...
link.exe
echo [nasm] Assembling main kernel...
nasm -f bin -o ./build/system.img kernel.asm