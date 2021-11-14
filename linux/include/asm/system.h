static __inline void move_to_user_mode()
{
	__asm mov	eax, esp
	__asm push	0x17
	__asm push	eax
	__asm pushfd
	__asm push	0x0F
	__asm push	LN1
	__asm iretd
LN1 :
	__asm mov	eax, 0x17
	__asm mov	ds, ax
	__asm mov	es, ax
	__asm mov	fs, ax
	__asm mov	gs, ax
}

#define sti()	__asm sti
#define cli()	__asm cli
#define nop()	__asm nop

#define iret()	__asm iretd

static __inline void _set_gate(desc_table gate_addr, int type, int dpl, void *addr)
{
	gate_addr->a = ((unsigned long)addr & 0x0000FFFF) + \
		0x00080000;
	gate_addr->b = ((unsigned long)addr & 0xFFFF0000) + \
		(0x8000 + (dpl << 13) + (type << 8));
}

#define set_intr_gate(n,addr) \
	_set_gate(&idt[n],14,0,addr)

#define set_trap_gate(n,addr) \
	_set_gate(&idt[n],15,0,addr)

#define set_system_gate(n,addr) \
	_set_gate(&idt[n],15,3,addr)

static __inline void _set_tssldt_desc(char *n, void *addr, char type)
{
	*(short*)n = 0x68;
	*(short*)(n + 2) = (unsigned long)addr & 0xFFFF;
	*(n + 4) = ((unsigned long)addr >> 16) & 0xFF;
	*(n + 5) = type;
	*(n + 6) = 0;
	*(n + 7) = (char)(((unsigned long)addr >> 28));
}

#define set_tss_desc(n,addr) _set_tssldt_desc(((char*)(n)), addr, 0x89)
#define set_ldt_desc(n,addr) _set_tssldt_desc(((char*)(n)), addr, 0x82)
