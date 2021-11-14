extern __inline unsigned char get_fs_byte(const char *addr)
{
	unsigned register char _v;

	__asm mov	edi, addr
	__asm mov	al, fs :[edi];
	__asm mov	_v, al

	return _v;
}

extern __inline unsigned short get_fs_word(const unsigned short *addr)
{
	unsigned short _v;

	__asm mov	edi, addr
	__asm mov	ax, fs :[edi];
	__asm mov	_v, ax

	return _v;
}

extern __inline unsigned long get_fs_long(const unsigned long *addr)
{
	unsigned long _v;

	__asm mov	edi, addr
	__asm mov	eax, fs :[edi];
	__asm mov	_v, eax

	return _v;
}

extern __inline void put_fs_byte(char val, char *addr)
{
	__asm mov	al, val
	__asm mov	edi, addr
	__asm mov	fs : [edi], al
}

extern __inline void put_fs_word(short val, short * addr)
{
	__asm mov	ax, val
	__asm mov	edi, addr
	__asm mov	fs : [edi], ax
}

extern __inline void put_fs_long(unsigned long val, unsigned long * addr)
{
	__asm mov	eax, val
	__asm mov	edi, addr
	__asm mov	fs : [edi], eax
}

/*
* Someone who knows GNU asm better than I should double check the followig.
* It seems to work, but I don't know if I'm doing something subtly wrong.
* --- TYT, 11/24/91
* [ nothing wrong here, Linus ]
*/

extern __inline unsigned long get_fs()
{
	unsigned short _v;

	__asm mov	ax, fs
	__asm mov	_v, ax

	return _v;
}

extern __inline unsigned long get_ds()
{
	unsigned short _v;

	__asm mov	ax, ds
	__asm mov	_v, ax

	return _v;
}

extern __inline void set_fs(unsigned long val)
{
	__asm mov	eax, val
	__asm mov	fs, ax
}
