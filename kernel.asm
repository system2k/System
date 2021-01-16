	use16
	org 0x7C00

BootSector:
	mov ah, 0x00	; reset disk
	mov dl, 0		; drive number
	int 0x13		; call bios disk service

	mov ah, 0x02	; command to read sectors into memory
	mov al, 40		; read 40 sectors
	mov dl, 0x80	; drive number
	mov ch, 0		; cylinder number
	mov dh, 0		; head number
	mov cl, 2		; sector start number
	mov bx, sys_stage2	; load sector to this address
	int 0x13

	jmp sys_stage2

	times ((0x200 - 2) - ($ - $$)) db 0x00	; pad file to 510
	dw 0xAA55					; add 2 magic bytes


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
	or eax, 0b00000001
	mov cr0, eax
	jmp CODE_SEG:BeginKernel32
	hlt
	ret
	
[bits 32]
	
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


	; remap PIC
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

; Timer Interrupt
addr_irq0:
	pusha
	mov al, 0x20
	out 0x20, al ;; EOI
	popa
	iret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Keyboard Interrupt
addr_irq1:
	pusha
	mov al, 0x20
	out 0x20, al ; acknowledge keyboard interrupt to PIC (prevents hanging keyboard)
	popa
	iret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
addr_irq2: ;; IRQ 2?
	pusha
	mov al, 0x20
	out 0x20, al ;; EOI
	popa
	iret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
addr_irq3:
	pusha
	mov al, 0x20
	out 0x20, al ;; EOI
	popa
	iret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
addr_irq4:
	pusha
	mov al, 0x20
	out 0x20, al ;; EOI
	popa
	iret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
addr_irq5:
	pusha
	mov al, 0x20
	out 0x20, al ;; EOI
	popa
	iret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
addr_irq6:
	pusha
	mov al, 0x20
	out 0x20, al ;; EOI
	popa
	iret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
addr_irq7:
	pusha
	mov al, 0x20
	out 0x20, al ;; EOI
	popa
	iret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
addr_irq8:
	pusha
	mov al, 0x20
	out 0x20, al ;; EOI
	popa
	iret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
addr_irq9:
	pusha
	mov al, 0x20
	out 0x20, al ;; EOI
	popa
	iret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
addr_irq10:
	pusha
	mov al, 0x20
	out 0x20, al ;; EOI
	popa
	iret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
addr_irq11:
	pusha
	mov al, 0x20
	out 0x20, al ;; EOI
	popa
	iret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
addr_irq12:
	pusha

	mov eax, 0
	mov edx, 0
	mov [Packet_PS2Pos], al
dataloop:
	xor eax, eax
	xor ebx, ebx
	in al, 0x64 ; status
	mov [tempIrq12AL], al

	mov bl, [tempIrq12AL]
	and bl, 0x20
	cmp bl, 0x20
	jne exit_ps2_loop
	
	mov bl, [tempIrq12AL]
	and bl, 0x01
	cmp bl, 0
	jz exit_ps2_loop
	
	in al, 0x60 ; buffer
	
	; store packet
	mov ebx, Packet_PS2Mouse
	mov cl, [Packet_PS2Pos]
	and ecx, 0xFF
	add ebx, ecx
	mov [ebx], al

	cmp cl, 0
	je case_0
	cmp cl, 1
	je case_1
	cmp cl, 2
	je case_2
	cmp cl, 3
	je case_3
	jmp case_def
case_0:
	inc cl
	mov [Packet_PS2Pos], cl
	jmp case_def
case_1:
	inc cl
	mov [Packet_PS2Pos], cl
	jmp case_def
case_2:
	inc cl
	mov [Packet_PS2Pos], cl
	call process_ps2_packet
	jmp case_def
case_3:
	; wheel?
	inc cl
	mov [Packet_PS2Pos], cl
	call process_ps2_packet
	jmp case_def
case_def:
	jmp dataloop
exit_ps2_loop:
	mov al, 0x20
	out 0xA0, al
	mov al, 0x20
	out 0x20, al ;; EOI
	popa
	iret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
addr_irq13:
	pusha
	mov al, 0x20
	out 0x20, al ;; EOI
	popa
	iret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
addr_irq14:
	pusha
	mov al, 0x20
	out 0x20, al ;; EOI
	popa
	iret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
addr_irq15:
	pusha
	mov al, 0x20
	out 0xA0, al ;; EOI
	mov al, 0x20
	out 0x20, al ;; EOI
	popa
	iret
	
KernelYieldEvent:
	pusha
KernelYieldLoop:
	hlt
	mov al, byte [EventReady]
	cmp al, 0x00
	je KernelYieldLoop
	
	; copy packet to event buffer
	mov ebx, 8500000
	mov al, [Packet_PS2Mouse]
	mov [ebx], al
	mov ebx, 8500001
	mov al, [Packet_PS2Mouse + 1]
	mov [ebx], al
	mov ebx, 8500002
	mov al, [Packet_PS2Mouse + 2]
	mov [ebx], al
	mov ebx, 8500003
	mov al, [Packet_PS2Mouse + 3]
	mov [ebx], al
	mov ebx, 8500004
	mov al, [Packet_PS2Mouse + 4]
	mov [ebx], al
	
	mov al, 0x00
	mov byte [EventReady], al
	
	popa
	mov eax, 7777
	ret

process_ps2_packet:
	; event is now ready to be dispatched
	mov al, 0x01
	mov byte [EventReady], al
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
	sti

	;;; Memory locations
	;;; 7000000: kernel read/write data
	;;; 8000000: kernel variable initialization space
	;;; 9000000: kernel readonly data
	;;; 8500000: kernel event buffer


	; transfer kernel data to another location
	mov edx, codeDataSection
	mov ecx, 7000000
	mov ebx, 0
moveLoop1:
	mov al, [edx]
	mov [ecx], al
	inc ebx
	inc edx
	inc ecx
	cmp ebx, codeReadonlyData - codeDataSection
	jl moveLoop1
	
	mov edx, codeReadonlyData
	mov ecx, 9000000
	mov ebx, 0
moveLoop2:
	mov al, [edx]
	mov [ecx], al
	inc ebx
	inc edx
	inc ecx
	cmp ebx, kernelBytecode - codeReadonlyData
	jl moveLoop2


	jmp BeginKernel
	
;;;;;;;;;;;;;;;; Kernel Data ;;;;;;;;;;;;;;;;

codeDataSection:
	incbin "./build/exec_data.bin"
codeReadonlyData:
	incbin "./build/exec_rdata.bin"
kernelBytecode:
	mov eax, [VideoMemPtr]
	push KernelYieldEvent
	push eax
	call kernelBytecodeStart
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