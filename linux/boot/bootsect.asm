;
; bootsect.s		(C) 1991 Linus Torvalds
;

; bootsect.s is loaded at 0x7c00 by the bios-startup routines, and moves
; iself out of the way to address 0x90000, and jumps there.
;
; It then loads 'setup' directly after itself (0x90200), and the system
; at 0x10000, using BIOS interrupts. 
;
; NOTE; currently system is at most 8*65536 bytes long. This should be no
; problem, even in the future. I want to keep it simple. This 512 kB
; kernel size should be enough, especially as this doesn't contain the
; buffer cache as in minix
;
; The loader has been made as simple as possible, and continuos
; read errors will result in a unbreakable loop. Reboot by hand. It
; loads pretty fast by getting whole sectors at a time whenever possible.

	.model	tiny, c
	.686P

OPTION	casemap:none

PUBLIC	WinMainCRTStartup

; SYS_SIZE is the number of clicks (16 bytes) to be loaded.
; 0x3000 is 0x30000 bytes = 196kB, more than enough for current
; versions of linux

SYSSIZE		=	3000h

SETUPLEN	=	4		; nr of setup-sectors
BOOTSEG		=	07C0h	; original address of boot-sector
INITSEG		=	9000h	; we move boot here - out of the way
SETUPSEG	=	9020h	; setup starts here
SYSSEG		=	1000h	; system loaded at 0x10000 (65536).
ENDSEG		=	SYSSEG+SYSSIZE	; where to stop loading

; ROOT_DEV:	0x000 - same type of floppy as boot.
; 0x301 - first partition on first drive etc

ROOT_DEV	=	0301h

sread		=	ds:[01C0h]
head		=	ds:[01C2h]
track		=	ds:[01C4h]
sectors		=	ds:[01C6h]
msg1		=	ds:[01C8h]
root_dev	=	ds:[01FCh]

.code

	ORG	0

WinMainCRTStartup:
	mov		ax, BOOTSEG
	mov		ds, ax
	mov		ax, INITSEG
	mov		es, ax
	mov		cx, 256
	xor		si, si
	xor		di, di
	rep		movsw
	push	INITSEG
	push	0020h		; OFFSET go
	retf
	
	ORG	0020h

go:
	mov		ax, cs
	mov		ds, ax
	mov		es, ax
; put stack at 0x9ff00.
	mov		ss, ax
	mov		sp, 0FF00h	; arbitrary value >>512
	
; load the setup-sectors directly after the bootblock.
; Note that 'es' is already set up.

load_setup:
	mov		dx, 0000h	; drive 0, head 0
	mov		cx,	0002h	; sector 2, track 0
	mov		bx, 0200h	; address = 512, in INITSEG
	mov		ax, 0200h + SETUPLEN	; service 2, nr of sectors
	int		13h			; read it
	jnc		ok_load_setup	; ok - continue
	mov		dx,	0000h
	mov		ax, 0000h	; reset the diskette
	int		13h
	jmp		load_setup
	
ok_load_setup:
	
; Get disk drive parameters, specifically nr of sectors/track

	mov		dl, 00h
	mov		ax, 0800h	; AH=8 is get drive parameters
	int		13h
	mov		ch, 00h
	mov		sectors, cx
	mov		ax, INITSEG
	mov		es, ax
	
; Print some inane message
	mov		ah, 03h
	xor		bh, bh
	int		10h
	mov		cx, SIZEOF $msg1
	mov		bx, 0007h	; page 0, attribute 7 (normal)
	mov		bp, OFFSET msg1
	mov		ax, 1301h
	int		10h
	
; ok, we've written the message, now
; we want to load the system (at 0x10000)
	mov		ax, SYSSEG
	mov		es, ax		; segment of 0x010000
	call	read_it
	call	kill_motor
	
; After that we check which root-device to use. If the device is
; defined (!= 0), nothing is done and the given device is used.
; Otherwise, either /dev/PS0 (2,28) or /dev/at0 (2,8), depending
; on the number of sectors that the BIOS reports currently.
	
	mov		ax, root_dev
	cmp		ax, 0
	jne		root_defined
	mov		bx, sectors
	mov		ax, 0208h	; /dev/ps0 - 1.2Mb
	cmp		bx, 15
	je		root_defined
	mov		ax, 021Ch	; /dev/PS0 - 1.44Mb
	cmp		bx, 18
	je		root_defined
undef_root:
	jmp		undef_root
root_defined:
	mov		root_dev, ax
	
; after that (everyting loaded), we jump to 
; the setup-routine loaded directly after
; the bootblock:

	push	SETUPSEG
	push	0
	retf

; This routine loads the system at address 0x10000, making sure
; no 64kB boundaries are crossed. We try to load it as fast as
; possible, loading whole tracks whenever we can.
;
; in:	es - starting address segment (normally 0x1000)	

read_it:
	mov		ax, es
	test	ax, 0FFFh
die:
	jne		die			; es must be at 64kB boundary
	xor		bx, bx		; bx is starting address within segment
rp_read:
	mov		ax, es
	cmp		ax, ENDSEG	; have we loaded all yet?
	jb		ok1_read
	ret
ok1_read:
	mov		ax, sectors
	sub		ax, sread
	mov		cx, ax
	shl		cx, 9
	add		cx, bx
	jnc		ok2_read
	je		ok2_read
	xor		ax, ax
	sub		ax, bx
	shr		ax, 9
ok2_read:
	call	read_track
	mov		cx, ax
	add		ax, sread
	cmp		ax, sectors
	jne		ok3_read
	mov		ax, 1
	sub		ax, head
	jne		ok4_read
	inc		WORD PTR track
ok4_read:
	mov		head, ax
	xor		ax, ax
ok3_read:
	mov		sread, ax
	shl		cx, 9
	add		bx, cx
	jnc		rp_read
	mov		ax, es
	add		ax, 1000h
	mov		es, ax
	xor		bx, bx
	jmp		rp_read
	
read_track:
	push	ax
	push	bx
	push	cx
	push	dx
	mov		dx, track
	mov		cx, sread
	inc		cx
	mov		ch, dl
	mov		dx, head
	mov		dh, dl
	mov		dl, 0
	and		dx, 0100h
	mov		ah, 2
	int		13h
	jc		bad_rt
	pop		dx
	pop		cx
	pop		bx
	pop		ax
	ret
bad_rt:
	mov		ax, 0
	mov		dx, 0
	int		13h
	pop		dx
	pop		cx
	pop		bx
	pop		ax
	jmp		read_track
	
; This procedure turns off the floppy drive motor, so
; that we enter the kernel in a known state, and
; don't have to worry about it later.

kill_motor:
	push	dx
	mov		dx, 03F2h
	mov		al, 0
	outsb
	pop		dx
	ret
	
	ORG	01C0h

$sread		WORD	1+SETUPLEN	; sectors read of current track
$head		WORD	0				; current head
$track		WORD	0				; current track
$sectors	WORD	0
$msg1		BYTE	0Dh,0Ah,'Loading system ...',0Dh,0Ah,0Dh,0Ah
	
	ORG	01FCh

_root_dev	WORD	ROOT_DEV
_boot_flag	WORD	0AA55h

END