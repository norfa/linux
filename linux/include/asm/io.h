static __inline void outb(unsigned char value, unsigned short port)
{
	__asm mov	al, value
	__asm mov	dx, port
	__asm out	dx, al
}

static __inline unsigned char inb(unsigned short port)
{
	unsigned char _v;

	__asm mov	dx, port
	__asm in	al, dx
	__asm mov	_v, al

	return _v;
}

static __inline void outb_p(unsigned char value, unsigned short port)
{
	__asm mov	al, value
	__asm mov	dx, port
	__asm out	dx, al
	__asm jmp	LN1
LN1 :
	__asm jmp	LN2
LN2 :
	;
}

static __inline unsigned char inb_p(unsigned short port)
{
	unsigned char _v;

	__asm mov	dx, port
	__asm in	al, dx
	__asm jmp	LN1
LN1 :
	__asm jmp	LN2
LN2 :
	__asm mov	_v, al

	return _v;
}