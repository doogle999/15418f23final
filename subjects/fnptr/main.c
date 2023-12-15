void outputSeven(int* number)
{
	*number = 7;
}

void outputFive(int* number)
{
	*number = 5;
}

void outputThree(int* number)
{
	*number = 3;
}

void outputZero(int* number)
{
	*number = 0;
}

int compare(char const* a, char const* b)
{	
	while(*a && (*a == *b)) { a++; b++; }
	return *(unsigned char const*)a - *(unsigned char const*)b;
}

int main(int argc, char** argv)
{
	int result = 0;
	
	if(argc != 2)
	{
		return 1;
	}

	void (*outputNumberFn)(int*) = outputZero;

	if(compare(argv[1], "three") == 0) outputNumberFn = outputThree;
	else if(compare(argv[1], "five") == 0) outputNumberFn = outputFive;
	else if(compare(argv[1], "seven") == 0) outputNumberFn = outputSeven;

	outputNumberFn(&result);

	return result;
}
