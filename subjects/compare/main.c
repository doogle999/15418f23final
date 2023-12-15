int compare(char const* a, char const* b)
{	
	while(*a && (*a == *b)) { a++; b++; }
	return *(unsigned char const*)a - *(unsigned char const*)b;
}

#define COMP(word) compare(argv[1], word) < 0

int main(int argc, char** argv)
{
	if(argc != 2)
	{
		return -1;
	}

	if(compare(argv[1], "secret") == 0)
	{
		return 1337;
	}
    if(COMP("izpeit"))
	{
		if(COMP("ecoyoj"))
		{
			if(COMP("bmehuh"))
			{
				if(COMP("aaewem"))
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
				if(COMP("ctbthw"))
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
			if(COMP("hlilri"))
			{
				if(COMP("fhhcjm"))
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
				if(COMP("hwlyzl"))
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
	else
	{
		if(COMP("pjujqn"))
		{
			if(COMP("noassv"))
			{
				if(COMP("muupuy"))
				{
					return 8;
				}
				else
				{
					return 9;
				}
			}
			else
			{
				if(COMP("ozqnao"))
				{
					return 10;
				}
				else
				{
					return 11;
				}
			}
		}
		else
		{
			if(COMP("wxbiot"))
			{
				if(COMP("qztmzt"))
				{
					return 12;
				}
				else
				{
					return 13;
				}
			}
			else
			{
				if(COMP("zyyfbw"))
				{
					return 14;
				}
				else
				{
					return 15;
				}
			}
		}
	}
	
	/* if(compare(argv[1], "hello") >= 0) */
	/* { */
	/* 	if(compare(argv[1], "zaz") >= 0) */
	/* 	{ */
	/* 		if(compare(argv[1], "zzz") >= 0) */
	/* 		{ */
	/* 			return 0; */
	/* 		} */
	/* 		else */
	/* 		{ */
	/* 			return 1; */
	/* 		} */
	/* 	} */
	/* 	else */
	/* 	{ */
	/* 		if(compare(argv[1], "sus") >= 0) */
	/* 		{ */
	/* 			return 2; */
	/* 		} */
	/* 		else */
	/* 		{ */
	/* 			return 3; */
	/* 		} */
	/* 	} */
	/* } */
	/* else */
	/* { */
	/* 	if(compare(argv[1], "bca") >= 0) */
	/* 	{ */
	/* 		if(compare(argv[1], "gull") >= 0) */
	/* 		{ */
	/* 			return 4; */
	/* 		} */
	/* 		else */
	/* 		{ */
	/* 			return 5; */
	/* 		} */
	/* 	} */
	/* 	else */
	/* 	{ */
	/* 		if(compare(argv[1], "aca") >= 0) */
	/* 		{ */
	/* 			return 6; */
	/* 		} */
	/* 		else */
	/* 		{ */
	/* 			return 7; */
	/* 		} */
	/* 	} */
	/* } */
}
