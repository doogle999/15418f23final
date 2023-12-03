#include <malloc.h>

int main(int argc, char** argv)
{
	unsigned int const BUFFER_COUNT = 100;
	
	int* buffer = malloc(BUFFER_COUNT * sizeof(int));

	if(!buffer)
	{
		return 1;
	}

	for(unsigned int i = 0; i < BUFFER_COUNT; i++)
	{
		buffer[i] = i;
	}

	free(buffer);

	return 0;
}
