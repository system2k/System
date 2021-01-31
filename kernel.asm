	use16
	org 0x7C00

BootSector:
	jmp beginBoot
	times (0x100 - ($ - $$)) db 0x00
drvNum: db 0x00
beginBoot:
	; the bios provides boot drive on dl, preserve it
	mov [drvNum], dl
	
	; set segment offset to give us more address space
	mov ax, 0x7E0
	mov es, ax
	
	mov ah, 0x02		; command to read sectors into memory
	mov al, 120			; read 120 sectors
	mov dl, [drvNum]	; drive number
	mov ch, 0			; cylinder number
	mov dh, 0			; head number
	mov cl, 2
	mov bx, 0			; load sector to this address
	int 0x13
	
	; reset segment
	mov ax, 0x0000
	mov es, ax
	
	jmp 0x0000:sys_stage2

	; pad bootsector and add magic bytes
	times ((0x200 - 2) - ($ - $$)) db 0x00
	dw 0xAA55


sys_stage2:
	jmp BeginInitSystem

	; scratch space for the vesa struct
STRUCTPTR:
	times 512 db 0x00

SysStartMsg:
	db "Starting System...", 13, 10, 0

PrintMessage:
	mov ebx, SysStartMsg
	mov ah, 0x0E
ContMessage:
	mov al, [ebx]
	cmp al, 0
	je EndMessage
	inc ebx
	int 0x10
	jmp ContMessage
EndMessage:
	ret
	
	
BeginInitSystem:
	call PrintMessage
	jmp InitializeGraphics
	
	
	
VideoMemPtr: dd 0x00000000
	
InitializeGraphics:
	; get information about mode 0x0112
	mov ax, 0x4F01
	mov cx, 0x0112
	mov di, STRUCTPTR
	int 0x10
	
	; get pointer from received information
	mov eax, STRUCTPTR
	add eax, 40 ; pointer number at offset 40
	mov ebx, [eax]
	mov [VideoMemPtr], ebx
	
	; enter the mode
	mov ax, 0x4F02 ; vesa mode
	mov bx, 0x0112 ; 640x480x24
	int 0x10
	
enterProtMode:
	cli
	lgdt [gdt_descriptor]
	mov eax, cr0
	or eax, 0b00000001 ; set "protected mode enable" flag
	mov cr0, eax
	jmp CODE_SEG:BeginKernel32 ; set CS register and jump to kernel
	hlt
	ret
	
[bits 32]

; set up the Global Descriptor Table
; the GDT determines the current ring level and permission levels for memory ranges,
; such as read, write, and code execute.
gdt_start:
gdt_null:
	dd 0x0
	dd 0x0
	
gdt_code:
	dw 0xFFFF
	dw 0x0
	db 0x0
	db 10011010b
	db 11001111b
	db 0x0
	
gdt_data:
	dw 0xFFFF
	dw 0x0
	db 0x0
	db 10010010b
	db 11001111b
	db 0x0
gdt_end:
	
gdt_descriptor:
	dw gdt_end - gdt_start
	dd gdt_start
	
CODE_SEG equ gdt_code - gdt_start
DATA_SEG equ gdt_data - gdt_start




IDT_table:
	times 2048 db 0x00
IDT_ptr_high:	dd 0x00000000
IDT_ptr_low:	dd 0x00000000


BeginKernel32:
	mov ax, DATA_SEG
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax
	mov ss, ax


	;ebp was observed to start at 0x00006EF0 (varies)
	;increments by 4 on protected mode, 2 on real mode

	; program the timer interrupt to about 60 ticks per second
	mov ax, 1193181 / 45
	out 0x40, al
	mov al, ah
	out 0x40, al

	; remap PIC
	; move interrupts from 0-15 to 32-47
	; exceptions are now at 0-15
	mov al, 0x11
	out 0x20, al
	mov al, 0x11
	out 0xA0, al
	mov al, 0x20
	out 0x21, al
	mov al, 0x28
	out 0xA1, al
	mov al, 0x04
	out 0x21, al
	mov al, 0x02
	out 0xA1, al
	mov al, 0x01
	out 0x21, al
	mov al, 0x01
	out 0xA1, al
	mov al, 0x00
	out 0x21, al
	mov al, 0x00
	out 0xA1, al

%macro InterruptDesc 2 ; %1: function, %2: offset
	mov eax, %1
	and eax, 0xFFFF
	mov [0 + IDT_table + %2 * 8], ax ;; offset_lowerbits
	mov eax, 0x08
	mov [2 + IDT_table + %2 * 8], ax ;; selector
	mov eax, 0
	mov [4 + IDT_table + %2 * 8], al ;; zero
	mov eax, 0x8E
	mov [5 + IDT_table + %2 * 8], al ;; type_attr
	mov eax, %1
	and eax, 0xFFFF0000
	shr eax, 16
	mov [6 + IDT_table + %2 * 8], ax ;; offset_higherbits
%endmacro

	InterruptDesc addr_exception, 0
	InterruptDesc addr_exception, 1
	InterruptDesc addr_exception, 2
	InterruptDesc addr_exception, 3
	InterruptDesc addr_exception, 4
	InterruptDesc addr_exception, 5
	InterruptDesc addr_exception, 6
	InterruptDesc addr_exception, 7
	InterruptDesc addr_exception, 8
	InterruptDesc addr_exception, 9
	InterruptDesc addr_exception, 10
	InterruptDesc addr_exception, 11
	InterruptDesc addr_exception, 12
	InterruptDesc addr_exception, 13
	InterruptDesc addr_exception, 14
	InterruptDesc addr_exception, 15

	InterruptDesc addr_irq0, 32 ; timer interrupt
	InterruptDesc addr_irq1, 33 ; keyboard
	InterruptDesc addr_irq2, 34
	InterruptDesc addr_irq3, 35
	InterruptDesc addr_irq4, 36
	InterruptDesc addr_irq5, 37
	InterruptDesc addr_irq6, 38
	InterruptDesc addr_irq7, 39
	InterruptDesc addr_irq8, 40
	InterruptDesc addr_irq9, 41
	InterruptDesc addr_irq10, 42
	InterruptDesc addr_irq11, 43
	InterruptDesc addr_irq12, 44 ; ps/2
	InterruptDesc addr_irq13, 45
	InterruptDesc addr_irq14, 46
	InterruptDesc addr_irq15, 47

	jmp beginIDT

; ps/2 mouse packet data
tempIrq12AL: db 0x00
Packet_PS2Mouse: db 0x00, 0x00, 0x00, 0x00, 0x00
Packet_PS2Pos: db 0x00

EventReady: db 0x00

KernIntTablePtr: dd 0x00000000

KernelSetIRQ:
	mov eax, [esp + 4]
	mov [KernIntTablePtr], eax
	sti
	ret

; *** Exceptions ***
; for now, just make all of them shut down the system
addr_exception:
	call blankScreen
	jmp EndKernelLoop

; *** Interrupts ***
addr_irq0:
	pusha
	mov eax, [KernIntTablePtr]
	call [eax]
	popa
	iret
addr_irq1:
	pusha
	mov eax, [KernIntTablePtr]
	call [eax + 4]
	popa
	iret
addr_irq2:
	pusha
	mov eax, [KernIntTablePtr]
	call [eax + 8]
	popa
	iret
addr_irq3:
	pusha
	mov eax, [KernIntTablePtr]
	call [eax + 12]
	popa
	iret
addr_irq4:
	pusha
	mov eax, [KernIntTablePtr]
	call [eax + 16]
	popa
	iret
addr_irq5:
	pusha
	mov eax, [KernIntTablePtr]
	call [eax + 20]
	popa
	iret
addr_irq6:
	pusha
	mov eax, [KernIntTablePtr]
	call [eax + 24]
	popa
	iret
addr_irq7:
	pusha
	mov eax, [KernIntTablePtr]
	call [eax + 28]
	popa
	iret
addr_irq8:
	pusha
	mov eax, [KernIntTablePtr]
	call [eax + 32]
	popa
	iret
addr_irq9:
	pusha
	mov eax, [KernIntTablePtr]
	call [eax + 36]
	popa
	iret
addr_irq10:
	pusha
	mov eax, [KernIntTablePtr]
	call [eax + 40]
	popa
	iret
addr_irq11:
	pusha
	mov eax, [KernIntTablePtr]
	call [eax + 44]
	popa
	iret
addr_irq12:
	pusha
	mov eax, [KernIntTablePtr]
	call [eax + 48]
	popa
	iret
addr_irq13:
	pusha
	mov eax, [KernIntTablePtr]
	call [eax + 52]
	popa
	iret
addr_irq14:
	pusha
	mov eax, [KernIntTablePtr]
	call [eax + 56]
	popa
	iret
addr_irq15:
	pusha
	mov eax, [KernIntTablePtr]
	call [eax + 60]
	popa
	iret

KernelYieldEvent:
	;pusha
;KernelYieldLoop:
	hlt
	;popa
	ret

beginIDT:
	; load idt
	mov eax, IDT_table
	and eax, 0xFFFF
	shl eax, 16
	add eax, 2048
	mov [IDT_ptr_high], eax

	mov eax, IDT_table
	shr eax, 16
	mov [IDT_ptr_low], eax

	mov eax, IDT_ptr_high
	lidt [eax]
	
	jmp BeginKernel
	
	
blankScreen:
	mov eax, [VideoMemPtr]
	mov ecx, 0
	mov bl, 255
blankScreenLoop:
	mov [eax], bl
	inc eax
	inc ecx
	cmp ecx, 640 * 480 * 3
	jl blankScreenLoop
	ret
	

reloc_memBase: dd 0x00100000
reloc_memBss: dd 0x00000000
reloc_memGlobVar: dd 0x00000000
reloc_kernelEntry: dd 0x00000000

; Initialize memory region with zeros
; ebx: starting addr
; ecx: buffer size
memRegion_init:
	add ecx, ebx
memRegInitLoop:
	mov byte [ebx], 0x00
	inc ebx
	cmp ebx, ecx
	jl memRegInitLoop
	ret

; runtime relocation
processKernelReloc:
	mov eax, codeRelocationData
kernRelocLoop:
	mov bl, [eax]
	add eax, 1
	cmp bl, 1 ; data
	je kreloc_data
	cmp bl, 2 ; rdata
	je kreloc_rdata
	cmp bl, 3 ; bss
	je kreloc_bss
	cmp bl, 4 ; glob
	je kreloc_glob
	cmp bl, 5 ; text
	je kreloc_text
	cmp bl, 6 ; bssSize
	je kreloc_bssSize
	cmp bl, 7 ; globVarSize
	je kreloc_globVarSize
	cmp bl, 8 ; entry
	je kreloc_entry
	jmp kernRelocStop
kreloc_data:
	mov ecx, [eax]
	add ecx, kernelBytecodeStart
	mov edx, ecx
	mov ecx, [ecx]
	add ecx, codeDataSection
	mov [edx], ecx
	add eax, 4
	jmp kernRelocLoop
kreloc_rdata:
	mov ecx, [eax]
	add ecx, kernelBytecodeStart
	mov edx, ecx
	mov ecx, [ecx]
	add ecx, codeReadonlyData
	mov [edx], ecx
	add eax, 4
	jmp kernRelocLoop
kreloc_bss:
	mov ecx, [eax]
	add ecx, kernelBytecodeStart
	mov edx, ecx
	mov ecx, [ecx]
	add ecx, [reloc_memBss]
	mov [edx], ecx
	add eax, 4
	jmp kernRelocLoop
kreloc_glob:
	mov ecx, [eax]
	add ecx, kernelBytecodeStart
	mov edx, ecx
	mov ecx, [ecx]
	add ecx, [reloc_memGlobVar]
	add eax, 4
	mov ebx, [eax]
	add ecx, ebx
	mov [edx], ecx
	add eax, 4
	jmp kernRelocLoop
kreloc_text:
	mov ecx, [eax]
	add ecx, kernelBytecodeStart
	mov edx, ecx
	mov ecx, [ecx]
	add ecx, kernelBytecodeStart
	mov [edx], ecx
	add eax, 4
	jmp kernRelocLoop
kreloc_bssSize:
	; set BSS ptr to memory base and increment memory base by size of BSS
	mov ecx, [reloc_memBase]
	mov [reloc_memBss], ecx
	mov ebx, [eax]
	add ecx, ebx
	mov [reloc_memBase], ecx
	; initialize region
	mov ebx, [reloc_memBss]
	mov ecx, [eax]
	call memRegion_init
	add eax, 4
	jmp kernRelocLoop
kreloc_globVarSize:
	mov ecx, [reloc_memBase]
	mov [reloc_memGlobVar], ecx
	mov ebx, [eax]
	add ecx, ebx
	mov [reloc_memBase], ecx
	; initialize region
	mov ebx, [reloc_memGlobVar]
	mov ecx, [eax]
	call memRegion_init
	add eax, 4
	jmp kernRelocLoop
kreloc_entry:
	mov ecx, [eax]
	mov [reloc_kernelEntry], ecx
	add eax, 4
	jmp kernRelocLoop
kernRelocStop:
	ret

;;;;;;;;;;;;;;;; Kernel Data ;;;;;;;;;;;;;;;;

codeRelocationData:
	incbin "./build/reloc.bin"
codeDataSection:
	incbin "./build/exec_data.bin"
codeReadonlyData:
	incbin "./build/exec_rdata.bin"
kernelBytecode:
	call processKernelReloc
	mov eax, [VideoMemPtr]
	push KernelSetIRQ
	push KernelYieldEvent
	push eax
	mov eax, kernelBytecodeStart
	add eax, [reloc_kernelEntry]
	call eax
	jmp kernelBytecodeEnd
kernelBytecodeStart:
	incbin "./build/exec_code.bin"
kernelBytecodeEnd:
	jmp EndKernel



	
BeginKernel:
	jmp kernelBytecode
EndKernel:
	cli
EndKernelLoop:
	hlt
	jmp EndKernelLoop



	times (0x200000 - ($ - $$)) db 0x00