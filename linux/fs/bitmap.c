/*
 *  linux/fs/bitmap.c
 *
 *  (C) 1991  Linus Torvalds
 */

/* bitmap.c contains the code that handles the inode and block bitmaps */
#include <string.h>

#include <linux\sched.h>
#include <linux\kernel.h>

static __inline void clear_block(void *addr)
{
	__asm mov	edi, addr
	__asm mov	ecx, BLOCK_SIZE / 4
	__asm xor	eax, eax
	__asm cld
	__asm rep	stosd
}

static __inline int set_bit(int nr, void *addr)
{
	register int res;

	__asm xor	eax, eax
	__asm mov	edi, addr
	__asm mov	edx, nr
	__asm bts	DWORD PTR[edi], edx
	__asm setb	al
	__asm mov	res, eax

	return res;
}

static __inline int clear_bit(int nr, void *addr)
{
	register int res;

	__asm xor	eax, eax
	__asm mov	edi, addr
	__asm mov	edx, nr
	__asm btr	DWORD PTR[edi], edx
	__asm setnb	al
	__asm mov	res, eax

	return res;
}

static __inline int find_first_zero(void *addr)
{
	int __res;

	__asm xor	ecx, ecx
	__asm mov	esi, addr
	__asm cld
LN1 :
	__asm lodsd
	__asm not	eax
	__asm bsf	edx, eax
	__asm je	LN2
	__asm add	ecx, edx
	__asm jmp	LN3
LN2 :
	__asm add	ecx, 32
	__asm cmp	ecx, 8192
	__asm jl	LN1
LN3 :
	__asm mov	__res, ecx

	return __res;
}

void free_block(int dev, int block)
{
	struct super_block * sb;
	struct buffer_head * bh;

	if (!(sb = get_super(dev)))
		panic("trying to free block on nonexistent device");
	if (block < sb->s_firstdatazone || block >= sb->s_nzones)
		panic("trying to free block not in datazone");
	bh = get_hash_table(dev, block);
	if (bh) {
		if (bh->b_count != 1) {
			printk("trying to free block (%04x:%d), count=%d\n",
				dev, block, bh->b_count);
			return;
		}
		bh->b_dirt = 0;
		bh->b_uptodate = 0;
		brelse(bh);
	}
	block -= sb->s_firstdatazone - 1;
	if (clear_bit(block & 8191, sb->s_zmap[block / 8192]->b_data)) {
		printk("block (%04x:%d) ", dev, block + sb->s_firstdatazone - 1);
		panic("free_block: bit already cleared");
	}
	sb->s_zmap[block / 8192]->b_dirt = 1;
}

int new_block(int dev)
{
	struct buffer_head * bh;
	struct super_block * sb;
	int i, j;

	if (!(sb = get_super(dev)))
		panic("trying to get new block from nonexistant device");
	j = 8192;
	for (i = 0; i < 8; i++)
		if (bh = sb->s_zmap[i])
			if ((j = find_first_zero(bh->b_data)) < 8192)
				break;
	if (i >= 8 || !bh || j >= 8192)
		return 0;
	if (set_bit(j, bh->b_data))
		panic("new_block: bit already set");
	bh->b_dirt = 1;
	j += i * 8192 + sb->s_firstdatazone - 1;
	if (j >= sb->s_nzones)
		return 0;
	if (!(bh = getblk(dev, j)))
		panic("new_block: cannot get block");
	if (bh->b_count != 1)
		panic("new block: count is != 1");
	clear_block(bh->b_data);
	bh->b_uptodate = 1;
	bh->b_dirt = 1;
	brelse(bh);
	return j;
}

void free_inode(struct m_inode * inode)
{
	struct super_block * sb;
	struct buffer_head * bh;

	if (!inode)
		return;
	if (!inode->i_dev) {
		memset(inode, 0, sizeof(*inode));
		return;
	}
	if (inode->i_count > 1) {
		printk("trying to free inode with count=%d\n", inode->i_count);
		panic("free_inode");
	}
	if (inode->i_nlinks)
		panic("trying to free inode with links");
	if (!(sb = get_super(inode->i_dev)))
		panic("trying to free inode on nonexistent device");
	if (inode->i_num < 1 || inode->i_num > sb->s_ninodes)
		panic("trying to free inode 0 or nonexistant inode");
	if (!(bh = sb->s_imap[inode->i_num >> 13]))
		panic("nonexistent imap in superblock");
	if (clear_bit(inode->i_num & 8191, bh->b_data))
		printk("free_inode: bit already cleared.\n\r");
	bh->b_dirt = 1;
	memset(inode, 0, sizeof(*inode));
}

struct m_inode * new_inode(int dev)
{
	struct m_inode * inode;
	struct super_block * sb;
	struct buffer_head * bh;
	int i, j;

	if (!(inode = get_empty_inode()))
		return NULL;
	if (!(sb = get_super(dev)))
		panic("new_inode with unknown device");
	j = 8192;
	for (i = 0; i < 8; i++)
		if (bh = sb->s_imap[i])
			if ((j = find_first_zero(bh->b_data))<8192)
				break;
	if (!bh || j >= 8192 || j + i * 8192 > sb->s_ninodes) {
		iput(inode);
		return NULL;
	}
	if (set_bit(j, bh->b_data))
		panic("new_inode: bit already set");
	bh->b_dirt = 1;
	inode->i_count = 1;
	inode->i_nlinks = 1;
	inode->i_dev = dev;
	inode->i_uid = current->euid;
	inode->i_gid = (unsigned char)current->egid;
	inode->i_dirt = 1;
	inode->i_num = j + i * 8192;
	inode->i_mtime = inode->i_atime = inode->i_ctime = CURRENT_TIME;
	return inode;
}
