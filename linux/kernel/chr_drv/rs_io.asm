; linux/kernel/rs_io.s
;
; (C) 1991  Linus Torvalds

; rs_io.s
;
; This module implements the rs232 io interrupts.

	.686P
	.model flat, c

OPTION	casemap:none

PUBLIC	rs1_interrupt
PUBLIC	rs2_interrupt
EXTRN	do_tty_interrupt:PROC
EXTRN	table_list:DWORD

$size		=	1024	; must be power of two !
						; and must match the value
						; in tty_io.c!!!

; these are the offsets into the read/write buffer structures

rs_addr		=	0
head		=	4
tail		=	8
proc_list	=	12
buf			=	16

startup		=	256		; chars left in write queue when we restart it

.code

; These are the actual interrupt routines. They look where
; the interrupt is coming from, and take appropriate action.

ALIGN	DWORD
rs1_interrupt:
	push	table_list+8
	jmp		rs_int
ALIGN	DWORD
rs2_interrupt:
	push	table_list+16
rs_int:
	push	edx
	push	ecx
	push	ebx
	push	eax
	push	es
	push	ds					; as this is an interrupt, we cannot
	push	10h					; know that bs is ok. Load it
	pop		ds
	push	10
	pop		es
	mov		edx, 24[esp]
	mov		edx, [edx]
	mov		edx, rs_addr[edx]
	add		edx, 2				; interrupt ident. reg
rep_int:
	xor		eax, eax
	in		al, dx
	test	al, 1
	jne		$end
	cmp		al, 6				; this shouldn't happen, but ...
	ja		$end
	mov		ecx, 24[esp]
	push	edx
	sub		edx, 2
	call	jmp_table[eax*2]	; NOTE! not *4, bit0 is 0 already
	pop		edx
	jmp		rep_int
$end:
	mov		al, 20h
	out		20h, al				; EOI
	pop		ds
	pop		es
	pop		eax
	pop		ebx
	pop		ecx
	pop		edx
	add		esp, 4				; jump over _table_list entry
	iretd
	
jmp_table	DWORD	modem_status,write_char,read_char,line_status

ALIGN	DWORD
modem_status:
	add		edx, 6				; clear intr by reading modem status reg
	in		al, dx
	ret
	
ALIGN	DWORD
line_status:
	add		edx, 5				; clear intr by reading line status reg.
	in		al, dx
	ret
	
ALIGN	DWORD
read_char:
	in		al, dx
	mov		edx, ecx
	sub		edx, table_list
	shr		edx, 3
	mov		ecx, [ecx]			; read-queue
	mov		ebx, head[ecx]
	mov		buf[ecx+ebx], al
	inc		ebx
	and		ebx, $size-1
	cmp		ebx, tail[ecx]
	je		@F
	mov		head[ecx], ebx
@@:
	push	edx
	call	do_tty_interrupt
	add		esp, 4
	ret

ALIGN	DWORD
write_char:
	mov		ecx, 4[ecx]			; write-queue
	mov		ebx, head[ecx]
	sub		ebx, tail[ecx]
	and		ebx, $size-1		; nr chars in queue
	je		write_buffer_empty
	cmp		ebx, startup
	ja		@F
	mov		ebx, proc_list[ecx]	; wake up sleeping process
	test	ebx, ebx			; is there any?
	je		@F
	mov		DWORD PTR [ebx], 0
@@:
	mov		ebx, tail[ecx]
	mov		al, buf[ecx+ebx]
	out		dx, al
	inc		ebx
	and		ebx, $size-1
	mov		tail[ecx], ebx
	cmp		ebx, head[ecx]
	je		write_buffer_empty
	ret
	
ALIGN	DWORD
write_buffer_empty:
	mov		ebx, proc_list[ecx]	; wake up sleeping process
	test	ebx, ebx			; is there any?
	je		@F
	mov		DWORD PTR [ebx], 0
@@:
	inc		edx
	in		al, dx
	jmp		$+2
	jmp		$+2
	and		al, 0Dh
	out		dx, al
	ret
	
END