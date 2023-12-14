int checkIfGood(int x)
{
	return x == 2;
}

int compare(char const* a, char const* b)
{	
	while(*a && (*(a++) == *(b++))) {}
	return *(unsigned char const*)a - *(unsigned char const*)b;
}

int main(int argc, char** argv)
{
    int outbuffer[3];
	
	if(checkIfGood(argc))
	{
		return 1;
	}

	if(compare(argv[1], "123"))
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

	return 0;
}
