#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "preprocessing.h"

// nasm -f win64 avx512.asm -o sneaky.obj
// g++ sneaky.obj main.cpp -o test.exe
// test.exe

extern void SneakySnake(int len, char* ReadSeq, char* RefSeq, int EditThreshold, int IterationNo);

int main() {
    int i;
    int bit;
    char RefSeq[] = "ACGTNA";
    char ReadSeq[] = "ACGTACGTACGTACGTN";
    int len = strlen(ReadSeq);
    int EditThreshold = 1;
    int KmerSize = 4;
    int DebugMode = 0;
    int IterationNo = 1;

    printf("Original RefSeq: %s\n", RefSeq);
    printf("Original ReadSeq: %s\n\n", ReadSeq);

    preprocess(RefSeq, ReadSeq, len);

    //checking preprocessed

    //printf("Processed RefSeq: ");
    //for (i = 0; i < (len + 1) / 2; i++) {
    //    for (bit = 7; bit >= 0; bit--)
    //        printf("%d", ((RefSeq[i] >> bit) & 1));
    //    printf(" ");  // space after every 8 bits
    //}


    //printf("\nProcessed ReadSeq: ");
    //for (i = 0; i < (len + 1) / 2; i++) {
    //    for (bit = 7; bit >= 0; bit--)
    //        printf("%d", ((ReadSeq[i] >> bit) & 1));
    //    printf(" ");
    //}

    SneakySnake(len, ReadSeq, RefSeq, EditThreshold, IterationNo);

    printf("After:  ");
    for (i = 0; i < len; ++i) printf("%d ", (unsigned char)ReadSeq[i]);
    printf("\n");
    //int result = SneakySnake(len, RefSeq, ReadSeq, EditThreshold, KmerSize, DebugMode, IterationNo);

    return 0;
}
