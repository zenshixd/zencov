#include <stdio.h> 

void otherFn(int* i);

int main() {
    int i = 0;
    otherFn(&i);
    if (i == 0) {
        i = 1;
    }
    return i;
}
