
firmware/firmware.elf:     file format elf32-littleriscv


Disassembly of section .text:

00000000 <_start>:
   0:	68000113          	li	sp,1664
   4:	00000297          	auipc	t0,0x0
   8:	7fc28293          	addi	t0,t0,2044 # 800 <_kernel_stack_top>
   c:	34029073          	csrw	mscratch,t0
  10:	00000297          	auipc	t0,0x0
  14:	03028293          	addi	t0,t0,48 # 40 <default_trap_handler>
  18:	30529073          	csrw	mtvec,t0
  1c:	0d800293          	li	t0,216
  20:	0d800313          	li	t1,216

00000024 <clear_bss_loop>:
  24:	0062d663          	bge	t0,t1,30 <bss_done>
  28:	0002a023          	sw	zero,0(t0)
  2c:	0291                	addi	t0,t0,4
  2e:	bfdd                	j	24 <clear_bss_loop>

00000030 <bss_done>:
  30:	20b5                	jal	9c <main>

00000032 <infinity_loop>:
  32:	a001                	j	32 <infinity_loop>
  34:	00000013          	nop
  38:	00000013          	nop
  3c:	00000013          	nop

00000040 <default_trap_handler>:
  40:	a001                	j	40 <default_trap_handler>
	...

0000004c <swap>:
  4c:	4198                	lw	a4,0(a1)
  4e:	411c                	lw	a5,0(a0)
  50:	c118                	sw	a4,0(a0)
  52:	c19c                	sw	a5,0(a1)
  54:	8082                	ret
  56:	0001                	nop

00000058 <bubble_sort>:
  58:	4785                	li	a5,1
  5a:	02b7dc63          	bge	a5,a1,92 <bubble_sort+0x3a>
  5e:	00259613          	slli	a2,a1,0x2
  62:	962a                	add	a2,a2,a0
  64:	00450813          	addi	a6,a0,4
  68:	4505                	li	a0,1
  6a:	0001                	nop
  6c:	87c2                	mv	a5,a6
  6e:	02b55363          	bge	a0,a1,94 <bubble_sort+0x3c>
  72:	0001                	nop
  74:	ffc7a703          	lw	a4,-4(a5)
  78:	4394                	lw	a3,0(a5)
  7a:	00e6d563          	bge	a3,a4,84 <bubble_sort+0x2c>
  7e:	fed7ae23          	sw	a3,-4(a5)
  82:	c398                	sw	a4,0(a5)
  84:	0791                	addi	a5,a5,4
  86:	fec797e3          	bne	a5,a2,74 <bubble_sort+0x1c>
  8a:	15fd                	addi	a1,a1,-1
  8c:	1671                	addi	a2,a2,-4
  8e:	fca59fe3          	bne	a1,a0,6c <bubble_sort+0x14>
  92:	8082                	ret
  94:	15fd                	addi	a1,a1,-1
  96:	1671                	addi	a2,a2,-4
  98:	bfd1                	j	6c <bubble_sort+0x14>
	...

0000009c <main>:
  9c:	1141                	addi	sp,sp,-16
  9e:	0b000513          	li	a0,176
  a2:	45a9                	li	a1,10
  a4:	c606                	sw	ra,12(sp)
  a6:	3f4d                	jal	58 <bubble_sort>
  a8:	40b2                	lw	ra,12(sp)
  aa:	4501                	li	a0,0
  ac:	0141                	addi	sp,sp,16
  ae:	8082                	ret
