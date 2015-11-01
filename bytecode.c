#include <stdio.h>
#define MAX_CHAR 32
int main (int argc, const char **argv)
{
	FILE * f = fopen (argv[1], "r");
	unsigned char buffer[MAX_CHAR];
	size_t s = 0;
	do
	{
		size_t a = 0;
		s = fread (buffer, sizeof (unsigned char), MAX_CHAR, f);
		for (a = 0; a < s; ++a)
		{
			printf ("%3u, ", buffer[a]);
		}
		printf ("\n");
	}
	while (s > 0);

	fclose (f);
	return 0;
}
