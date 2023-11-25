
test:     file format elf32-littleriscv


Disassembly of section .plt:

000102f0 <_PROCEDURE_LINKAGE_TABLE_>:
   102f0:	97 23 00 00 33 03 c3 41 03 ae 03 d1 13 03 43 fd     .#..3..A......C.
   10300:	93 82 03 d1 13 53 23 00 83 a2 42 00 67 00 0e 00     .....S#...B.g...

00010310 <__libc_start_main@plt>:
   10310:	00002e17          	auipc	t3,0x2
   10314:	cf8e2e03          	lw	t3,-776(t3) # 12008 <__libc_start_main@GLIBC_2.34>
   10318:	000e0367          	jalr	t1,t3
   1031c:	00000013          	nop

00010320 <printf@plt>:
   10320:	00002e17          	auipc	t3,0x2
   10324:	cece2e03          	lw	t3,-788(t3) # 1200c <printf@GLIBC_2.33>
   10328:	000e0367          	jalr	t1,t3
   1032c:	00000013          	nop

Disassembly of section .text:

00010330 <_start>:
   10330:	2839                	jal	1034e <load_gp>
   10332:	87aa                	mv	a5,a0
   10334:	00000517          	auipc	a0,0x0
   10338:	08a50513          	add	a0,a0,138 # 103be <main>
   1033c:	4582                	lw	a1,0(sp)
   1033e:	0050                	add	a2,sp,4
   10340:	ff017113          	and	sp,sp,-16
   10344:	4681                	li	a3,0
   10346:	4701                	li	a4,0
   10348:	880a                	mv	a6,sp
   1034a:	37d9                	jal	10310 <__libc_start_main@plt>
   1034c:	9002                	ebreak

0001034e <load_gp>:
   1034e:	00002197          	auipc	gp,0x2
   10352:	4b218193          	add	gp,gp,1202 # 12800 <__global_pointer$>
   10356:	8082                	ret
	...

0001035a <deregister_tm_clones>:
   1035a:	6549                	lui	a0,0x12
   1035c:	6749                	lui	a4,0x12
   1035e:	00050793          	mv	a5,a0
   10362:	00070713          	mv	a4,a4
   10366:	00f70863          	beq	a4,a5,10376 <deregister_tm_clones+0x1c>
   1036a:	00000793          	li	a5,0
   1036e:	c781                	beqz	a5,10376 <deregister_tm_clones+0x1c>
   10370:	00050513          	mv	a0,a0
   10374:	8782                	jr	a5
   10376:	8082                	ret

00010378 <register_tm_clones>:
   10378:	6549                	lui	a0,0x12
   1037a:	00050793          	mv	a5,a0
   1037e:	6749                	lui	a4,0x12
   10380:	00070593          	mv	a1,a4
   10384:	8d9d                	sub	a1,a1,a5
   10386:	4025d793          	sra	a5,a1,0x2
   1038a:	81fd                	srl	a1,a1,0x1f
   1038c:	95be                	add	a1,a1,a5
   1038e:	8585                	sra	a1,a1,0x1
   10390:	c599                	beqz	a1,1039e <register_tm_clones+0x26>
   10392:	00000793          	li	a5,0
   10396:	c781                	beqz	a5,1039e <register_tm_clones+0x26>
   10398:	00050513          	mv	a0,a0
   1039c:	8782                	jr	a5
   1039e:	8082                	ret

000103a0 <__do_global_dtors_aux>:
   103a0:	1141                	add	sp,sp,-16
   103a2:	c422                	sw	s0,8(sp)
   103a4:	8181c783          	lbu	a5,-2024(gp) # 12018 <completed.0>
   103a8:	c606                	sw	ra,12(sp)
   103aa:	e789                	bnez	a5,103b4 <__do_global_dtors_aux+0x14>
   103ac:	377d                	jal	1035a <deregister_tm_clones>
   103ae:	4785                	li	a5,1
   103b0:	80f18c23          	sb	a5,-2024(gp) # 12018 <completed.0>
   103b4:	40b2                	lw	ra,12(sp)
   103b6:	4422                	lw	s0,8(sp)
   103b8:	0141                	add	sp,sp,16
   103ba:	8082                	ret

000103bc <frame_dummy>:
   103bc:	bf75                	j	10378 <register_tm_clones>

000103be <main>:
   103be:	1101                	add	sp,sp,-32
   103c0:	ce06                	sw	ra,28(sp)
   103c2:	cc22                	sw	s0,24(sp)
   103c4:	1000                	add	s0,sp,32
   103c6:	fea42623          	sw	a0,-20(s0)
   103ca:	feb42423          	sw	a1,-24(s0)
   103ce:	fec42583          	lw	a1,-20(s0)
   103d2:	67c1                	lui	a5,0x10
   103d4:	3ec78513          	add	a0,a5,1004 # 103ec <_IO_stdin_used+0x4>
   103d8:	37a1                	jal	10320 <printf@plt>
   103da:	4781                	li	a5,0
   103dc:	853e                	mv	a0,a5
   103de:	40f2                	lw	ra,28(sp)
   103e0:	4462                	lw	s0,24(sp)
   103e2:	6105                	add	sp,sp,32
   103e4:	8082                	ret
