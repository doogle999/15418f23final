
test:     file format elf32-littleriscv


Disassembly of section .plt:

00010290 <_PROCEDURE_LINKAGE_TABLE_>:
   10290:	97 23 00 00 33 03 c3 41 03 ae 03 d7 13 03 43 fd     .#..3..A......C.
   102a0:	93 82 03 d7 13 53 23 00 83 a2 42 00 67 00 0e 00     .....S#...B.g...

000102b0 <__libc_start_main@plt>:
   102b0:	00002e17          	auipc	t3,0x2
   102b4:	d58e2e03          	lw	t3,-680(t3) # 12008 <__libc_start_main@GLIBC_2.34>
   102b8:	000e0367          	jalr	t1,0(t3)
   102bc:	00000013          	addi	zero,zero,0

Disassembly of section .text:

000102c0 <_start>:
   102c0:	2839                	c.jal	102de <load_gp>
   102c2:	87aa                	c.mv	a5,a0
   102c4:	00000517          	auipc	a0,0x0
   102c8:	08c50513          	addi	a0,a0,140 # 10350 <main>
   102cc:	4582                	c.lwsp	a1,0(sp)
   102ce:	0050                	c.addi4spn	a2,sp,4
   102d0:	ff017113          	andi	sp,sp,-16
   102d4:	4681                	c.li	a3,0
   102d6:	4701                	c.li	a4,0
   102d8:	880a                	c.mv	a6,sp
   102da:	3fd9                	c.jal	102b0 <__libc_start_main@plt>
   102dc:	9002                	c.ebreak

000102de <load_gp>:
   102de:	00002197          	auipc	gp,0x2
   102e2:	52218193          	addi	gp,gp,1314 # 12800 <__global_pointer$>
   102e6:	8082                	c.jr	ra
	...

000102ea <deregister_tm_clones>:
   102ea:	6549                	c.lui	a0,0x12
   102ec:	6749                	c.lui	a4,0x12
   102ee:	00050793          	addi	a5,a0,0 # 12000 <__TMC_END__>
   102f2:	00070713          	addi	a4,a4,0 # 12000 <__TMC_END__>
   102f6:	00f70863          	beq	a4,a5,10306 <deregister_tm_clones+0x1c>
   102fa:	00000793          	addi	a5,zero,0
   102fe:	c781                	c.beqz	a5,10306 <deregister_tm_clones+0x1c>
   10300:	00050513          	addi	a0,a0,0
   10304:	8782                	c.jr	a5
   10306:	8082                	c.jr	ra

00010308 <register_tm_clones>:
   10308:	6549                	c.lui	a0,0x12
   1030a:	00050793          	addi	a5,a0,0 # 12000 <__TMC_END__>
   1030e:	6749                	c.lui	a4,0x12
   10310:	00070593          	addi	a1,a4,0 # 12000 <__TMC_END__>
   10314:	8d9d                	c.sub	a1,a5
   10316:	4025d793          	srai	a5,a1,0x2
   1031a:	81fd                	c.srli	a1,0x1f
   1031c:	95be                	c.add	a1,a5
   1031e:	8585                	c.srai	a1,0x1
   10320:	c599                	c.beqz	a1,1032e <register_tm_clones+0x26>
   10322:	00000793          	addi	a5,zero,0
   10326:	c781                	c.beqz	a5,1032e <register_tm_clones+0x26>
   10328:	00050513          	addi	a0,a0,0
   1032c:	8782                	c.jr	a5
   1032e:	8082                	c.jr	ra

00010330 <__do_global_dtors_aux>:
   10330:	1141                	c.addi	sp,-16
   10332:	c422                	c.swsp	s0,8(sp)
   10334:	8141c783          	lbu	a5,-2028(gp) # 12014 <completed.0>
   10338:	c606                	c.swsp	ra,12(sp)
   1033a:	e789                	c.bnez	a5,10344 <__do_global_dtors_aux+0x14>
   1033c:	377d                	c.jal	102ea <deregister_tm_clones>
   1033e:	4785                	c.li	a5,1
   10340:	80f18a23          	sb	a5,-2028(gp) # 12014 <completed.0>
   10344:	40b2                	c.lwsp	ra,12(sp)
   10346:	4422                	c.lwsp	s0,8(sp)
   10348:	0141                	c.addi	sp,16
   1034a:	8082                	c.jr	ra

0001034c <frame_dummy>:
   1034c:	bf75                	c.j	10308 <register_tm_clones>
	...

00010350 <main>:
   10350:	fe010113          	addi	sp,sp,-32
   10354:	00812e23          	sw	s0,28(sp)
   10358:	02010413          	addi	s0,sp,32
   1035c:	fea42623          	sw	a0,-20(s0)
   10360:	feb42423          	sw	a1,-24(s0)
   10364:	fec42783          	lw	a5,-20(s0)
   10368:	00179793          	slli	a5,a5,0x1
   1036c:	00078513          	addi	a0,a5,0
   10370:	01c12403          	lw	s0,28(sp)
   10374:	02010113          	addi	sp,sp,32
   10378:	00008067          	jalr	zero,0(ra)
