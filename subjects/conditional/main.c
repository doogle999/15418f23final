int checkIfGood(int x)
{
	return x == 1;
}

int main(int argc, char** argv)
{
    int outbuffer[3];
	
	if(checkIfGood(argc))
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
