#ifndef _SCHED_H
#define _SCHED_H

#define NR_TASKS 64
#define HZ 100

#define FIRST_TASK task[0]
#define LAST_TASK task[NR_TASKS-1]

#include <linux/head.h>
#include <linux/fs.h>
#include <linux/mm.h>
#include <signal.h>

#if (NR_OPEN > 32)
#error "Currently the close-on-exec-flags are in one word, max 32 files/proc"
#endif

#define TASK_RUNNING			0
#define TASK_INTERRUPTIBLE		1
#define TASK_UNINTERRUPTIBLE	2
#define TASK_ZOMBIE				3
#define TASK_STOPPED			4

#ifndef NULL
#define NULL ((void *) 0)
#endif

extern int copy_page_tables(unsigned long from, unsigned long to, long size);
extern int free_page_tables(unsigned long from, unsigned long size);

extern void sched_init(void);
extern void schedule(void);
extern void trap_init(void);
extern volatile void panic(const char * str);
extern int tty_write(unsigned minor, char * buf, int count);

typedef int(*fn_ptr)();

struct i387_struct {
	long	cwd;
	long	swd;
	long	twd;
	long	fip;
	long	fcs;
	long	foo;
	long	fos;
	long	st_space[20];	/* 8*10 bytes for each FP-reg = 80 bytes */
};

struct tss_struct {
	long	back_link;		/* 16 high bits zero */
	long	esp0;
	long	ss0;			/* 16 high bits zero */
	long	esp1;
	long	ss1;			/* 16 high bits zero */
	long	esp2;
	long	ss2;			/* 16 high bits zero */
	long	cr3;
	long	eip;
	long	eflags;
	long	eax, ecx, edx, ebx;
	long	esp;
	long	ebp;
	long	esi;
	long	edi;
	long	es;				/* 16 high bits zero */
	long	cs;				/* 16 high bits zero */
	long	ss;				/* 16 high bits zero */
	long	ds;				/* 16 high bits zero */
	long	fs;				/* 16 high bits zero */
	long	gs;				/* 16 high bits zero */
	long	ldt;			/* 16 high bits zero */
	long	trace_bitmap;	/* bits: trace 0, bitmap 16-31 */
	struct i387_struct i387;
};

struct task_struct {
	/* these are hardcoded - don't touch */
	long state;	/* -1 unrunnable, 0 runnable, >0 stopped */
	long counter;
	long priority;
	long signal;
	struct sigaction sigaction[32];
	long blocked;	/* bitmap of masked signals */
	/* various fields */
	int exit_code;
	unsigned long start_code, end_code, end_data, brk, start_stack;
	long pid, father, pgrp, session, leader;
	unsigned short uid, euid, suid;
	unsigned short gid, egid, sgid;
	long alarm;
	long utime, stime, cutime, cstime, start_time;
	unsigned short used_math;
	/* file system info */
	int tty;		/* -1 if no tty, so it must be signed */
	unsigned short umask;
	struct m_inode * pwd;
	struct m_inode * root;
	struct m_inode * executable;
	unsigned long close_on_exec;
	struct file * filp[NR_OPEN];
	/* ldt for this task 0 - zero 1 - cs 2 - ds&ss */
	struct desc_struct ldt[3];
	/* tss for this task */
	struct tss_struct tss;
};

/*
*  INIT_TASK is used to set up the first task table, touch at
* your own risk!. Base=0, limit=0x9ffff (=640kB)
*/
#define INIT_TASK \
	/* */			{ \
	/* state etc */		0, 15, 15, \
	/* signals */		0, { { 0, }, }, 0, \
	/* ec,brk... */		0, 0, 0, 0, 0, 0, \
	/* pid etc.. */		0, -1, 0, 0, 0, \
	/* uid etc */		0, 0, 0, 0, 0, 0, \
	/* alarm */			0, 0, 0, 0, 0, 0, \
	/* math */			0, \
	/* fs info */		-1, 0022, NULL, NULL, NULL, 0, \
	/* filp */			{ NULL, }, \
	/* */				{ \
	/* */					{ 0, 0 }, \
	/* ldt */				{ 0x9f, 0xc0fa00 }, \
	/* */					{ 0x9f, 0xc0f200 }, \
	/* */				}, \
	/* */				{ \
	/* tss */				0, PAGE_SIZE + (long)&init_task, 0x10, 0, 0, 0, 0, (long)&pg_dir, \
	/* */					0, 0, 0, 0, 0, 0, 0, 0, \
	/* */					0, 0, 0x17, 0x17, 0x17, 0x17, 0x17, 0x17, \
	/* */					_LDT(0), 0x80000000, \
	/* */					{ 0, } \
	/* */				} \
	/* */			} \

extern struct task_struct *task[NR_TASKS];
extern struct task_struct *last_task_used_math;
extern struct task_struct *current;
extern long volatile jiffies;
extern long startup_time;

#define CURRENT_TIME (startup_time+jiffies/HZ)

extern void add_timer(long jiffies, void(*fn)(void));
extern void sleep_on(struct task_struct ** p);
extern void interruptible_sleep_on(struct task_struct ** p);
extern void wake_up(struct task_struct ** p);

/*
* Entry into gdt where to find first TSS. 0-nul, 1-cs, 2-ds, 3-syscall
* 4-TSS0, 5-LDT0, 6-TSS1 etc ...
*/
#define FIRST_TSS_ENTRY 4
#define FIRST_LDT_ENTRY (FIRST_TSS_ENTRY+1)
#define _TSS(n) ((((unsigned long) n)<<4)+(FIRST_TSS_ENTRY<<3))
#define _LDT(n) ((((unsigned long) n)<<4)+(FIRST_LDT_ENTRY<<3))

static __inline void ltr(short n)
{
	short a = _TSS(n);

	__asm mov	ax, a
	__asm ltr	ax
}

static __inline void lldt(short n)
{
	short a = _LDT(n);

	__asm mov	ax, a
	__asm lldt	ax
}

#define str(n) \
	__asm xor	eax, eax \
	__asm str	ax \
	__asm sub	eax, FIRST_TSS_ENTRY << 3 \
	__asm shr	eax, 4 \
	__asm mov	n, eax

/*
*	switch_to(n) should switch tasks to task nr n, first
* checking that n isn't the current task, in which case it does nothing.
* This also clears the TS-flag if the task we switched to has used
* tha math co-processor latest.
*/
static __inline void switch_to(int n)
{
	struct { long a, b; } __tmp;

	if (task[n] == current) return;
	__tmp.b = _TSS(n);
	current = task[n];
	__asm jmp	FWORD PTR __tmp
	if (task[n] == last_task_used_math)
		__asm clts
}

static __inline _set_base(char *addr, unsigned long base)
{
	*((short*)(addr + 2)) = base & 0xFFFF;
	*(addr + 4) = (base >> 16) & 0xFF;
	*(addr + 7) = (char)(base >> 24);
}

static __inline _set_limit(char *addr, unsigned long limit)
{
	*(short*)addr = limit & 0xFFFF;
	*(addr + 6) = (*(addr + 6) & 0xF0) | ((limit >> 16) & 0xFF);
}

#define set_base(ldt,base) _set_base( ((char *)&(ldt)) , base )
#define set_limit(ldt,limit) _set_limit( ((char *)&(ldt)) , (limit-1)>>12 )

static __inline unsigned long _get_base(unsigned char *addr)
{
	unsigned long __base;

	__base = (*(addr + 7) << 24) + (*(addr + 4) << 16) + *(unsigned short*)(addr + 2);

	return __base;
}

#define get_base(ldt) _get_base( ((char *)&(ldt)) )

static __inline unsigned long get_limit(int segment)
{
	unsigned long __limit;

	__asm lsl	eax, segment
	__asm inc	eax
	__asm mov	__limit, eax

	return __limit;
}

#endif
