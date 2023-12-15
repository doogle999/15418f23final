int compare(char const* a, char const* b)
{	
	while(*a && (*a == *b)) { a++; b++; }
	return *(unsigned char const*)a - *(unsigned char const*)b;
}

#define COMP(word) compare(argv[1], word) >= 0

int main(int argc, char** argv)
{
	if(argc != 2)
	{
		return -1;
	}
	
	/* if(COMP()) */
	/* { */
	/* 	if(COMP()) */
	/* 	{ */
	/* 		if(COMP()) */
	/* 		{ */
	/* 			if(COMP()) */
	/* 			{ */
	/* 				return 0; */
	/* 			} */
	/* 			else */
	/* 			{ */
	/* 				return 1; */
	/* 			} */
	/* 		} */
	/* 		else */
	/* 		{ */
	/* 			if(COMP()) */
	/* 			{ */
	/* 				return 2; */
	/* 			} */
	/* 			else */
	/* 			{ */
	/* 				return 3; */
	/* 			} */
	/* 		} */
	/* 	} */
	/* 	else */
	/* 	{ */
	/* 		if(COMP()) */
	/* 		{ */
	/* 			if(COMP()) */
	/* 			{ */
	/* 				return 4; */
	/* 			} */
	/* 			else */
	/* 			{ */
	/* 				return 5; */
	/* 			} */
	/* 		} */
	/* 		else */
	/* 		{ */
	/* 			if(COMP()) */
	/* 			{ */
	/* 				return 6; */
	/* 			} */
	/* 			else */
	/* 			{ */
	/* 				return 7; */
	/* 			} */
	/* 		} */
	/* 	} */
	/* } */
	
	if(compare(argv[1], "hello") >= 0)
	{
		if(compare(argv[1], "zaz") >= 0)
		{
			if(compare(argv[1], "zzz") >= 0)
			{
				return 0;
			}
			else
			{
				return 1;
			}
		}
		else
		{
			if(compare(argv[1], "sus") >= 0)
			{
				return 2;
			}
			else
			{
				return 3;
			}
		}
	}
	else
	{
		if(compare(argv[1], "bca") >= 0)
		{
			if(compare(argv[1], "gull") >= 0)
			{
				return 4;
			}
			else
			{
				return 5;
			}
		}
		else
		{
			if(compare(argv[1], "aca") >= 0)
			{
				return 6;
			}
			else
			{
				return 7;
			}
		}
	}
}
