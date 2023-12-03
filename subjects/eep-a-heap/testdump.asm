
test:     file format elf32-littleriscv


Disassembly of section .plt:

00010310 <_PROCEDURE_LINKAGE_TABLE_>:
   10310:	97 23 00 00 33 03 c3 41 03 ae 03 cf 13 03 43 fd     .#..3..A......C.
   10320:	93 82 03 cf 13 53 23 00 83 a2 42 00 67 00 0e 00     .....S#...B.g...

00010330 <__libc_start_main@plt>:
   10330:	00002e17          	auipc	t3,0x2
   10334:	cd8e2e03          	lw	t3,-808(t3) # 12008 <__libc_start_main@GLIBC_2.34>
   10338:	000e0367          	jalr	t1,0(t3)
   1033c:	00000013          	addi	zero,zero,0

00010340 <free@plt>:
   10340:	00002e17          	auipc	t3,0x2
   10344:	ccce2e03          	lw	t3,-820(t3) # 1200c <free@GLIBC_2.33>
   10348:	000e0367          	jalr	t1,0(t3)
   1034c:	00000013          	addi	zero,zero,0

00010350 <malloc@plt>:
   10350:	00002e17          	auipc	t3,0x2
   10354:	cc0e2e03          	lw	t3,-832(t3) # 12010 <malloc@GLIBC_2.33>
   10358:	000e0367          	jalr	t1,0(t3)
   1035c:	00000013          	addi	zero,zero,0

Disassembly of section .text:

00010360 <_start>:
   10360:	2839                	c.jal	1037e <load_gp>
   10362:	87aa                	c.mv	a5,a0
   10364:	00000517          	auipc	a0,0x0
   10368:	08c50513          	addi	a0,a0,140 # 103f0 <main>
   1036c:	4582                	c.lwsp	a1,0(sp)
   1036e:	0050                	c.addi4spn	a2,sp,4
   10370:	ff017113          	andi	sp,sp,-16
   10374:	4681                	c.li	a3,0
   10376:	4701                	c.li	a4,0
   10378:	880a                	c.mv	a6,sp
   1037a:	3f5d                	c.jal	10330 <__libc_start_main@plt>
   1037c:	9002                	c.ebreak

0001037e <load_gp>:
   1037e:	00002197          	auipc	gp,0x2
   10382:	48218193          	addi	gp,gp,1154 # 12800 <__global_pointer$>
   10386:	8082                	c.jr	ra
	...

0001038a <deregister_tm_clones>:
   1038a:	6549                	c.lui	a0,0x12
   1038c:	6749                	c.lui	a4,0x12
   1038e:	00050793          	addi	a5,a0,0 # 12000 <__TMC_END__>
   10392:	00070713          	addi	a4,a4,0 # 12000 <__TMC_END__>
   10396:	00f70863          	beq	a4,a5,103a6 <deregister_tm_clones+0x1c>
   1039a:	00000793          	addi	a5,zero,0
   1039e:	c781                	c.beqz	a5,103a6 <deregister_tm_clones+0x1c>
   103a0:	00050513          	addi	a0,a0,0
   103a4:	8782                	c.jr	a5
   103a6:	8082                	c.jr	ra

000103a8 <register_tm_clones>:
   103a8:	6549                	c.lui	a0,0x12
   103aa:	00050793          	addi	a5,a0,0 # 12000 <__TMC_END__>
   103ae:	6749                	c.lui	a4,0x12
   103b0:	00070593          	addi	a1,a4,0 # 12000 <__TMC_END__>
   103b4:	8d9d                	c.sub	a1,a5
   103b6:	4025d793          	srai	a5,a1,0x2
   103ba:	81fd                	c.srli	a1,0x1f
   103bc:	95be                	c.add	a1,a5
   103be:	8585                	c.srai	a1,0x1
   103c0:	c599                	c.beqz	a1,103ce <register_tm_clones+0x26>
   103c2:	00000793          	addi	a5,zero,0
   103c6:	c781                	c.beqz	a5,103ce <register_tm_clones+0x26>
   103c8:	00050513          	addi	a0,a0,0
   103cc:	8782                	c.jr	a5
   103ce:	8082                	c.jr	ra

000103d0 <__do_global_dtors_aux>:
   103d0:	1141                	c.addi	sp,-16
   103d2:	c422                	c.swsp	s0,8(sp)
   103d4:	81c1c783          	lbu	a5,-2020(gp) # 1201c <completed.0>
   103d8:	c606                	c.swsp	ra,12(sp)
   103da:	e789                	c.bnez	a5,103e4 <__do_global_dtors_aux+0x14>
   103dc:	377d                	c.jal	1038a <deregister_tm_clones>
   103de:	4785                	c.li	a5,1
   103e0:	80f18e23          	sb	a5,-2020(gp) # 1201c <completed.0>
   103e4:	40b2                	c.lwsp	ra,12(sp)
   103e6:	4422                	c.lwsp	s0,8(sp)
   103e8:	0141                	c.addi	sp,16
   103ea:	8082                	c.jr	ra

000103ec <frame_dummy>:
   103ec:	bf75                	c.j	103a8 <register_tm_clones>
	...

000103f0 <main>:
   103f0:	fd010113          	addi	sp,sp,-48
   103f4:	02112623          	sw	ra,44(sp)
   103f8:	02812423          	sw	s0,40(sp)
   103fc:	03010413          	addi	s0,sp,48
   10400:	fca42e23          	sw	a0,-36(s0)
   10404:	fcb42c23          	sw	a1,-40(s0)
   10408:	06400793          	addi	a5,zero,100
   1040c:	fef42423          	sw	a5,-24(s0)
   10410:	fe842783          	lw	a5,-24(s0)
   10414:	00279793          	slli	a5,a5,0x2
   10418:	00078513          	addi	a0,a5,0
   1041c:	f35ff0ef          	jal	ra,10350 <malloc@plt>
   10420:	00050793          	addi	a5,a0,0
   10424:	fef42223          	sw	a5,-28(s0)
   10428:	fe442783          	lw	a5,-28(s0)
   1042c:	00079663          	bne	a5,zero,10438 <main+0x48>
   10430:	00100793          	addi	a5,zero,1
   10434:	0480006f          	jal	zero,1047c <main+0x8c>
   10438:	fe042623          	sw	zero,-20(s0)
   1043c:	0280006f          	jal	zero,10464 <main+0x74>
   10440:	fec42783          	lw	a5,-20(s0)
   10444:	00279793          	slli	a5,a5,0x2
   10448:	fe442703          	lw	a4,-28(s0)
   1044c:	00f707b3          	add	a5,a4,a5
   10450:	fec42703          	lw	a4,-20(s0)
   10454:	00e7a023          	sw	a4,0(a5)
   10458:	fec42783          	lw	a5,-20(s0)
   1045c:	00178793          	addi	a5,a5,1
   10460:	fef42623          	sw	a5,-20(s0)
   10464:	fec42703          	lw	a4,-20(s0)
   10468:	fe842783          	lw	a5,-24(s0)
   1046c:	fcf76ae3          	bltu	a4,a5,10440 <main+0x50>
   10470:	fe442503          	lw	a0,-28(s0)
   10474:	ecdff0ef          	jal	ra,10340 <free@plt>
   10478:	00000793          	addi	a5,zero,0
   1047c:	00078513          	addi	a0,a5,0
   10480:	02c12083          	lw	ra,44(sp)
   10484:	02812403          	lw	s0,40(sp)
   10488:	03010113          	addi	sp,sp,48
   1048c:	00008067          	jalr	zero,0(ra)
