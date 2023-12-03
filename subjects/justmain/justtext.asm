
test.o:     file format elf32-littleriscv


Disassembly of section .text:

00000000 <main>:
   0:	fe010113          	addi	sp,sp,-32
   4:	00812e23          	sw	s0,28(sp)
   8:	02010413          	addi	s0,sp,32
   c:	fea42623          	sw	a0,-20(s0)
  10:	feb42423          	sw	a1,-24(s0)
  14:	fec42783          	lw	a5,-20(s0)
  18:	00179793          	slli	a5,a5,0x1
  1c:	00078513          	addi	a0,a5,0
  20:	01c12403          	lw	s0,28(sp)
  24:	02010113          	addi	sp,sp,32
  28:	00008067          	jalr	zero,0(ra)
