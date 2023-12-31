int checkIfGood(int x)
{
	return x == 3;
}

int compare(char const* a, char const* b)
{	
	while(*a && (*a == *b)) { a++; b++; }
	return *(unsigned char const*)a - *(unsigned char const*)b;
}

int main(int argc, char** argv)
{
    int outbuffer[4];

	char word[4] = {65, 66, 67, 0};
	
	if(!checkIfGood(argc))
	{
		return argc + 100;
	}

	if(compare(argv[2], "word"))
	{
		outbuffer[3] = 0xaaaaaaaa;
	}

	if(compare(argv[1], "123") == 0)
	{
		outbuffer[0] = 7;
		outbuffer[1] = 8;
		outbuffer[2] = 9;
	}
	else
	{
		outbuffer[0] = 1;
		outbuffer[1] = 2;
		outbuffer[2] = 3;
	}

	return outbuffer[0] + outbuffer[1] + outbuffer[2];
}
