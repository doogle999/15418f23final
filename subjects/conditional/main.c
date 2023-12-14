int checkIfGood(int x)
{
	return x == 2;
}

int compare(char const* a, char const* b)
{	
	while(*a && (*a == *b)) { a++; b++; }
	return *(unsigned char const*)a - *(unsigned char const*)b;
}

int main(int argc, char** argv)
{
    int outbuffer[3];
	
	if(!checkIfGood(argc))
	{
		return 1;
	}

	char word[4] = {65, 66, 67, 0};

	if(compare(argv[1], "123") == 0)
	{
		outbuffer[0] = 0xffeeacac;
		outbuffer[1] = 8;
		outbuffer[2] = 9;
	}
	else
	{
		outbuffer[0] = 0xabcd1234;
		outbuffer[1] = 2;
		outbuffer[2] = 3;
	}

	return 0;
}
