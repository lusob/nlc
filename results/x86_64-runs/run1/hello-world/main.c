#include <stdio.h>

int main(void)
{
    if (puts("Hello, world!") == EOF)
        return 1;
    if (fflush(stdout) == EOF)
        return 1;
    return 0;
}
