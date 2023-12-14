int compare(char const* a, char const* b)
{	
	while(*a && (*a == *b)) { a++; b++; }
	return *(unsigned char const*)a - *(unsigned char const*)b;
}

int main(int argc, char** argv)
{
    if(argc != 3)
	{
		return -1;
	}

	return compare(argv[1], argv[2]);
}
