int main(int argc, char** argv)
{
	char buf[10];

	buf[0] = 'a';
	buf[1] = 'b';
	buf[2] = 'c';

	*(short*)(buf + 3) = 0x12ab;

	*(int*)(buf + 5) = 0xfedc9876;

	buf[8] = 'd';
	buf[9] = 'e';

	int intbuf[10];

	intbuf[0] = 15418;
	intbuf[1] = 0xa7aca7ac;
	intbuf[2] = intbuf[0] ^ intbuf[1];
	intbuf[3] = intbuf[0] + intbuf[1];
	intbuf[4] = intbuf[0] - intbuf[1];
	intbuf[5] = 3 << 4;
	intbuf[6] = -1 >> 4;
	intbuf[7] = (unsigned int)(-1) >> 4;
	
	return 0;
}
