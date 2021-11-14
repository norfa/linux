;
; setup.s		(C) 1991 Linus Torvalds
;
; setup.s is responsible for getting the system data from the BIOS,
; and putting them into the appropriate places in system memory.
; both setup.s and system has been loaded by the bootblock.
;
; This code asks the bios for memory/disk/other parameters, and
; puts them in a "safe" place: 0x90000-0x901FF, ie where the
; boot-block used to be. It is then up to the protected mode
; system to read them from there before the area is overwritten
; for buffer-blocks.

	.model	tiny, c
	.686P

OPTION	casemap:none

PUBLIC	WinMainCRTStartup

; NOTE! These had better be the same as in bootsect.s!

INITSEG		=	9000h	; we move boot here - out of the way
SYSSEG		=	1000h	; system loaded at 0x10000 (65536).
SETUPSEG	=	9020h	; this is the current segment

idt_48		=	ds:[0718h]
gdt_48		=	ds:[071Eh]

.code

	ORG	0

WinMainCRTStartup:

; ok, the read went well so we get current cursor position and save it for
; posterity.

	mov		ax, INITSEG	; this is done in bootsect already, but...
	mov		ds, ax
	mov		ah, 03h		; read cursor pos
	xor		bh, bh
	int		10h			; save it in known place, con_init fetches
	mov		ds:[0], dx	; it from 0x90000.
	
; Get memory size (extended mem, kB)

	mov		ah, 88h
	int		15h
	mov		ds:[2], ax
	
; Get video-card data:
	
	mov		ah, 0Fh
	int		10h
	mov		ds:[4], bx	; bh = display page
	mov		ds:[6], ax	; al = video mode, ah = window width
	
; check for EGA/VGA and some config parameters

	mov		ah, 12h
	mov		bl, 10h
	int		10h
	mov		ds:[8], ax
	mov		ds:[10], bx
	mov		ds:[12], cx
	
; Get hd0 data
	mov		ax, 0000h
	mov		ds, ax
	lds		si, ds:[4*41h]
	mov		ax, INITSEG
	mov		es, ax
	mov		di, 0080h
	mov		cx, 10h
	rep		movsb
	
; Get hd1 data

	mov		ax, 0000h
	mov		ds, ax
	lds		si, ds:[4*46h]
	mov		ax, INITSEG
	mov		es, ax
	mov		di, 0090h
	mov		cx, 10h
	rep		movsb
	
; Check that there IS a hd1 :-)

	mov		ax, 1500h
	mov		dl, 81h
	int		13h
	jc		no_disk1
	cmp		ah, 3
	je		is_disk1
no_disk1:
	mov		ax, INITSEG
	mov		es, ax
	mov		di, 0090h
	mov		cx, 10h
	mov		ax, 00h
	rep		stosb
is_disk1:

; now we want to move to protected mode ...

	cli					; no interrupts allowed !
	
; first we move the system to it's rightful place
	
	mov		ax, 0000h
	cld					; 'direction'=0, movs moves forward
do_move:
	mov		es, ax		; destination segment
	add		ax, 1000h
	cmp		ax, 9000h
	jz		end_move
	mov		ds, ax		; source segment
	xor		di, di
	xor		si, si
	mov		cx, 8000h
	rep		movsw
	jmp		do_move
	
; then we load the segment descriptors	
	
end_move:
	mov		ax, SETUPSEG		; right, forgot this at first. didn't work :-)
	mov		ds,	ax
	lidt	FWORD PTR idt_48	; load idt with 0,0
	lgdt	FWORD PTR gdt_48	; load gdt with whatever appropriate
	
; that was painless, now we enable A20

	call	empty_8042
	mov		al, 0D1h	; command write
	out		64h, al
	call	empty_8042
	mov		al, 0DFh	; A20 on
	out		60h, al
	call	empty_8042
	
; well, that went ok, I hope. Now we have to reprogram the interrupts :-(
; we put them right after the intel-reserved hardware interrupts, at
; int 0x20-0x2F. There they won't mess up anything. Sadly IBM really
; messed this up with the original PC, and they haven't been able to
; rectify it afterwards. Thus the bios puts interrupts at 0x08-0x0f,
; which is used for the internal hardware interrupts as well. We just
; have to reprogram the 8259's, and it isn't fun.

	mov		al, 11h		; initialization sequence
	out		20h, al		; send it to 8259A-1
	jmp		$+2
	jmp		$+2
	out		0A0h, al	; and to 8259A-2
	jmp		$+2
	jmp		$+2
	mov		al, 20h		; start of hardware int's (0x20)
	out		21h, al
	jmp		$+2
	jmp		$+2
	mov		al, 28h		; start of hardware int's 2 (0x28)
	out		0A1h, al
	jmp		$+2
	jmp		$+2
	mov		al, 04h		; 8259-1 is master
	out		21h, al
	jmp		$+2
	jmp		$+2
	mov		al, 02h		; 8259-2 is slave
	out		0A1h, al
	jmp		$+2
	jmp		$+2
	mov		al, 01h		; 8086 mode for both
	out		21h, al
	jmp		$+2
	jmp		$+2
	out		0A1h, al
	jmp		$+2
	jmp		$+2
	mov		al, 0FFh	; mask off all interrupts for now
	out		21h, al
	jmp		$+2
	jmp		$+2
	out		0A1h, al

; well, that certainly wasn't fun :-(. Hopefully it works, and we don't
; need no steenking BIOS anyway (except for the initial loading :-).
; The BIOS-routine wants lots of unnecessary data, and it's less
; "interesting" anyway. This is how REAL programmers do it.
;
; Well, now's the time to actually move into protected mode. To make
; things as simple as possible, we do no register set-up or anything,
; we let the gnu-compiled 32-bit programs do that. We just jump to
; absolute address 0x00000, in 32-bit protected mode.

	mov		ax, 0001h	; protected mode (PE) bit
	lmsw	ax			; This is it!
	push	0008h
	push	1000h
	retf

; This routine checks that the keyboard command queue is empty
; No timeout is used - if this hangs there is something wrong with
; the machine, and we probably couldn't proceed anyway.
empty_8042:
	jmp		$+2
	jmp		$+2
	in		al, 64h
	test	al, 02h		; is input buffer full?
	jnz		empty_8042	; yes - loop
	ret
	
	ORG	0700h
	
$gdt		WORD	0,0,0,0	; dummy

			WORD	07FFh	; 8Mb - limit=2047 (2048*4096=8Mb)
			WORD	0000h	; base address=0
			WORD	9A00h	; code read/exec
			WORD	00C0h	; granularity=4096, 386

			WORD	07FFh	; 8Mb - limit=2047 (2048*4096=8Mb)
			WORD	0000h	; base address=0
			WORD	9200h	; data read/write
			WORD	00C0h	; granularity=4096, 386
			
$idt_48		WORD	0		; idt limit=0
			WORD	0,0		; idt base=0L
			
$gdt_48		WORD	0800h	; gdt limit=2048, 256 GDT entries
			WORD	0200h+0700h,0009h	; gdt base = 0X9xxxx
	
	ORG	800h

END