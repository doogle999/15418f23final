
test:     file format elf32-littleriscv


Disassembly of section .plt:

00010290 <_PROCEDURE_LINKAGE_TABLE_>:
   10290:	97 23 00 00 33 03 c3 41 03 ae 03 d7 13 03 43 fd     .#..3..A......C.
   102a0:	93 82 03 d7 13 53 23 00 83 a2 42 00 67 00 0e 00     .....S#...B.g...

000102b0 <__libc_start_main@plt>:
   102b0:	00002e17          	auipc	t3,0x2
   102b4:	d58e2e03          	lw	t3,-680(t3) # 12008 <__libc_start_main@GLIBC_2.34>
   102b8:	000e0367          	jalr	t1,t3
   102bc:	00000013          	nop

Disassembly of section .text:

000102c0 <_start>:
   102c0:	2839                	jal	102de <load_gp>
   102c2:	87aa                	mv	a5,a0
   102c4:	00000517          	auipc	a0,0x0
   102c8:	08a50513          	add	a0,a0,138 # 1034e <main>
   102cc:	4582                	lw	a1,0(sp)
   102ce:	0050                	add	a2,sp,4
   102d0:	ff017113          	and	sp,sp,-16
   102d4:	4681                	li	a3,0
   102d6:	4701                	li	a4,0
   102d8:	880a                	mv	a6,sp
   102da:	3fd9                	jal	102b0 <__libc_start_main@plt>
   102dc:	9002                	ebreak

000102de <load_gp>:
   102de:	00002197          	auipc	gp,0x2
   102e2:	52218193          	add	gp,gp,1314 # 12800 <__global_pointer$>
   102e6:	8082                	ret
	...

000102ea <deregister_tm_clones>:
   102ea:	6549                	lui	a0,0x12
   102ec:	6749                	lui	a4,0x12
   102ee:	00050793          	mv	a5,a0
   102f2:	00070713          	mv	a4,a4
   102f6:	00f70863          	beq	a4,a5,10306 <deregister_tm_clones+0x1c>
   102fa:	00000793          	li	a5,0
   102fe:	c781                	beqz	a5,10306 <deregister_tm_clones+0x1c>
   10300:	00050513          	mv	a0,a0
   10304:	8782                	jr	a5
   10306:	8082                	ret

00010308 <register_tm_clones>:
   10308:	6549                	lui	a0,0x12
   1030a:	00050793          	mv	a5,a0
   1030e:	6749                	lui	a4,0x12
   10310:	00070593          	mv	a1,a4
   10314:	8d9d                	sub	a1,a1,a5
   10316:	4025d793          	sra	a5,a1,0x2
   1031a:	81fd                	srl	a1,a1,0x1f
   1031c:	95be                	add	a1,a1,a5
   1031e:	8585                	sra	a1,a1,0x1
   10320:	c599                	beqz	a1,1032e <register_tm_clones+0x26>
   10322:	00000793          	li	a5,0
   10326:	c781                	beqz	a5,1032e <register_tm_clones+0x26>
   10328:	00050513          	mv	a0,a0
   1032c:	8782                	jr	a5
   1032e:	8082                	ret

00010330 <__do_global_dtors_aux>:
   10330:	1141                	add	sp,sp,-16
   10332:	c422                	sw	s0,8(sp)
   10334:	8141c783          	lbu	a5,-2028(gp) # 12014 <completed.0>
   10338:	c606                	sw	ra,12(sp)
   1033a:	e789                	bnez	a5,10344 <__do_global_dtors_aux+0x14>
   1033c:	377d                	jal	102ea <deregister_tm_clones>
   1033e:	4785                	li	a5,1
   10340:	80f18a23          	sb	a5,-2028(gp) # 12014 <completed.0>
   10344:	40b2                	lw	ra,12(sp)
   10346:	4422                	lw	s0,8(sp)
   10348:	0141                	add	sp,sp,16
   1034a:	8082                	ret

0001034c <frame_dummy>:
   1034c:	bf75                	j	10308 <register_tm_clones>

0001034e <main>:
   1034e:	1101                	add	sp,sp,-32
   10350:	ce22                	sw	s0,28(sp)
   10352:	1000                	add	s0,sp,32
   10354:	fea42623          	sw	a0,-20(s0)
   10358:	feb42423          	sw	a1,-24(s0)
   1035c:	fec42783          	lw	a5,-20(s0)
   10360:	0786                	sll	a5,a5,0x1
   10362:	853e                	mv	a0,a5
   10364:	4472                	lw	s0,28(sp)
   10366:	6105                	add	sp,sp,32
   10368:	8082                	ret
