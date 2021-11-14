; linux/boot/head.s
; 
; (C) 1991  Linus Torvalds

; head.s contains the 32-bit startup code.
;
; NOTE!!! Startup happens at absolute address 0x00000000, which is also where
; the page directory will exist. The startup code will be overwritten by
; the page directory.

	.686P
	.model	flat, c

OPTION	casemap:none

PUBLIC	WinMainCRTStartup
PUBLIC	idt
PUBLIC	gdt
PUBLIC	pg_dir
PUBLIC	tmp_floppy_area
PUBLIC	_end
EXTRN	stack_start:DWORD
EXTRN	main:PROC
EXTRN	printk:PROC

pg_dir		=	0
_end		=	30000h

.code

; I put the kernel page tables right after the page directory,
; using 4 of them to span 16 Mb of physical memory. People with
; more than 16MB will have to expand this.

	ORG	0000h
pg0:

WinMainCRTStartup:
	mov		eax, 10h
	mov		ds, ax
	mov		es, ax
	mov		fs, ax
	mov		gs, ax
	lss		esp, FWORD PTR stack_start
	call	setup_idt
	call	setup_gdt
	mov		eax, 10h		; reload all the segment registers
	mov		ds, ax			; after changing gdt. CS was already
	mov		es, ax			; reloaded in 'setup_gdt'
	mov		fs, ax
	mov		gs, ax
	lss		esp, FWORD PTR stack_start
	xor		eax, eax
@@:
	inc		eax
	mov		ds:[00000000h], eax
	cmp		eax, [00100000h]
	je		@B

; NOTE! 486 should set bit 16, to check for write-protect in supervisor
; mode. Then it would be unnecessary with the "verify_area()"-calls.
; 486 users probably want to set the NE (#5) bit also, so as to use
; int 16 for math errors.
	
	mov		eax, cr0		; check math chip
	and		eax, 80000011h	; Save PG,PE,ET
; "orl $0x10020,%eax" here for 486 might be good
	or		eax, 02h		; set MP
	mov		cr0, eax
	call	check_x87
	jmp		after_page_tables
	
; We depend on ET to be correct. This checks for 287/387.

check_x87:
	fninit
	fstsw	ax
	cmp		ax, 0
	je		@F				; no coprocessor: have to set bits
	mov		eax, cr0
	xor		eax, 06h		; reset MP, set EM
	mov		cr0, eax
	ret
@@:
	fsetpm
	ret
	
; setup_idt
;
; sets up a idt with 256 entries pointing to
; ignore_int, interrupt gates. It then loads
; idt. Everything that wants to install itself
; in the idt-table may do so themselves. Interrupts
; are enabled elsewhere, when we can be relatively
; sure everything is ok. This routine will be over-
; written by the page tables.

setup_idt:
	lea		edx, ignore_int
	mov		eax, 00080000h
	mov		ax, dx			; selector = 0x0008 = cs
	mov		dx, 8E00h		; interrupt gate - dpl=0, present
	
	lea		edi, idt
	mov		ecx, 256
rp_sidt:
	mov		[edi], eax
	mov		[edi+4], edx
	add		edi, 8
	dec		ecx
	jne		rp_sidt
	lidt	FWORD PTR idt_descr
	ret
	
; setup_gdt
;
; This routines sets up a new gdt and loads it.
; Only two entries are currently built, the same
; ones that were built in init.s. The routine
; is VERY complicated at two whole lines, so this
; rather long comment is certainly needed :-).
; This routine will beoverwritten by the page tables.

setup_gdt:
	lgdt	FWORD PTR gdt_descr
	ret
	
; I put the kernel page tables right after the page directory,
; using 4 of them to span 16 Mb of physical memory. People with
; more than 16MB will have to expand this.
	
	ORG	1000h
pg1:

	ORG	2000h
pg2:

	ORG	3000h
pg3:

	ORG	4000h

; tmp_floppy_area is used by the floppy-driver when DMA cannot
; reach to a buffer-block. It needs to be aligned, so that it isn't
; on a 64kB border.

tmp_floppy_area	BYTE 1024 DUP (0)

after_page_tables:
	push	0			; These are the parameters to main :-)
	push	0
	push	0
	push	L6			; return address for main, if it decides to.
	push	main
	jmp		setup_paging
L6:
	jmp		L6			; main should never return here, but
						; just in case, we know what happens.

; This is the default interrupt "handler" :-)
int_msg		BYTE	'Unknown interrupt',0Dh,0Ah,0
ALIGN	DWORD
ignore_int:
	push	eax
	push	ecx
	push	edx
	push	ds
	push	es
	push	fs
	mov		eax, 10h
	mov		ds, ax
	mov		es, ax
	mov		fs, ax
	push	OFFSET int_msg
	call	printk
	pop		eax
	pop		fs
	pop		es
	pop		ds
	pop		edx
	pop		ecx
	pop		eax
	iretd

; setup_paging
;
; This routine sets up paging by setting the page bit
; in cr0. The page tables are set up, identity-mapping
; the first 16MB. The pager assumes that no illegal
; addresses are produced (ie >4Mb on a 4Mb machine).
;
; NOTE! Although all physical memory should be identity
; mapped by this routine, only the kernel page functions
; use the >1Mb addresses directly. All "normal" functions
; use just the lower 1Mb, or the local data space, which
; will be mapped to some other place - mm keeps track of
; that.
;
; For those with more memory than 16 Mb - tough luck. I've
; not got it, why should you :-) The source is here. Change
; it. (Seriously - it shouldn't be too difficult. Mostly
; change some constants etc. I left it at 16Mb, as my machine
; even cannot be extended past that (ok, but it was cheap :-)
; I've tried to show which constants to change by having
; some kind of marker at them (search for "16Mb"), but I
; won't guarantee that's all :-( )

ALIGN	DWORD
setup_paging:
	mov		ecx, 1024*5		; 5 pages - pg_dir+4 page tables
	xor		eax, eax
	xor		edi, edi			; pg_dir is at 0x000
	cld						
	rep		stosd
	mov		ds:[00h], pg0+07h	; set present bit/user r/w
	mov		ds:[04h], pg1+07h	; --------- " " ---------
	mov		ds:[08h], pg2+07h	; --------- " " ---------
	mov		ds:[0Ch], pg3+07h	; --------- " " ---------
	mov		edi, pg3+0FFCh
	mov		eax, 00FFF007h		; 16Mb - 4096 + 7 (r/w user,p)
	std
@@:
	stosd
	sub		eax, 1000h
	jge		@B
	xor		eax, eax			; pg_dir is at 0x0000
	mov		cr3, eax			; cr3 - page directory start
	mov		eax, cr0
	xor		eax, 80000000h
	mov		cr0, eax			; this also flushes prefetch-queue
	ret
				
ALIGN	DWORD
			WORD	0
idt_descr	WORD	256*8-1			; idt contains 256 entries
			DWORD	idt
ALIGN	DWORD
			WORD	0
gdt_descr	WORD	256*8-1			; so does gdt (not that that's any
			DWORD	gdt					; magic number, but it works for me :^)
					
ALIGN	QWORD
idt			QWORD	256 DUP (0)

gdt			QWORD	0000000000000000h	; NULL descriptor
			QWORD	00C09A0000000FFFh	; 16Mb
			QWORD	00C0920000000FFFh	; 16Mb
			QWORD	0000000000000000h	; TEMPORARY - don't use
			QWORD	252 DUP (0)			; space for LDT's and TSS's etc

END
