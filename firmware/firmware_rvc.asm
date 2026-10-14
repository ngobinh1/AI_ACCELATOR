
firmware/firmware_rvc.elf:     file format elf32-littleriscv


Disassembly of section .text:

00000000 <_start>:
   0:	68000113          	li	sp,1664
   4:	00000297          	auipc	t0,0x0
   8:	7fc28293          	addi	t0,t0,2044 # 800 <_kernel_stack_top>
   c:	34029073          	csrw	mscratch,t0
  10:	00000297          	auipc	t0,0x0
  14:	03028293          	addi	t0,t0,48 # 40 <default_trap_handler>
  18:	30529073          	csrw	mtvec,t0
  1c:	10800293          	li	t0,264
  20:	10800313          	li	t1,264

00000024 <clear_bss_loop>:
  24:	0062d663          	bge	t0,t1,30 <bss_done>
  28:	0002a023          	sw	zero,0(t0)
  2c:	0291                	addi	t0,t0,4
  2e:	bfdd                	j	24 <clear_bss_loop>

00000030 <bss_done>:
  30:	2095                	jal	94 <main>

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

00000056 <bubble_sort>:
  56:	4785                	li	a5,1
  58:	02b7da63          	bge	a5,a1,8c <bubble_sort+0x36>
  5c:	00259613          	slli	a2,a1,0x2
  60:	962a                	add	a2,a2,a0
  62:	00450813          	addi	a6,a0,4
  66:	4505                	li	a0,1
  68:	87c2                	mv	a5,a6
  6a:	02b55263          	bge	a0,a1,8e <bubble_sort+0x38>
  6e:	ffc7a703          	lw	a4,-4(a5)
  72:	4394                	lw	a3,0(a5)
  74:	00e6d563          	bge	a3,a4,7e <bubble_sort+0x28>
  78:	fed7ae23          	sw	a3,-4(a5)
  7c:	c398                	sw	a4,0(a5)
  7e:	0791                	addi	a5,a5,4
  80:	fec797e3          	bne	a5,a2,6e <bubble_sort+0x18>
  84:	15fd                	addi	a1,a1,-1
  86:	1671                	addi	a2,a2,-4
  88:	fea590e3          	bne	a1,a0,68 <bubble_sort+0x12>
  8c:	8082                	ret
  8e:	15fd                	addi	a1,a1,-1
  90:	1671                	addi	a2,a2,-4
  92:	bfd9                	j	68 <bubble_sort+0x12>

00000094 <main>:
  94:	1141                	addi	sp,sp,-16
  96:	0e000513          	li	a0,224
  9a:	45a9                	li	a1,10
  9c:	c606                	sw	ra,12(sp)
  9e:	3f65                	jal	56 <bubble_sort>
  a0:	40b2                	lw	ra,12(sp)
  a2:	4501                	li	a0,0
  a4:	0141                	addi	sp,sp,16
  a6:	8082                	ret
