#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "preprocessing.h"

// nasm -f win64 avx512.asm -o sneaky.obj
// g++ sneaky.obj main.cpp -o test.exe
// test.exe

extern "C" int SneakySnake(int ReadLength, char* RefSeq, char* ReadSeq, int EditThreshold, int KmerSize, int DebugMode, int IterationNo);

int main() {
    int i;
    int bit;
    char RefSeq[] = "ACGTNA";
    char ReadSeq[] = "ACGTA";

    int len = strlen(RefSeq);

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

    int result = SneakySnake(readLen, ref, read, editThresh, kmerSize, debugMode, iterNo);

    return 0;
}

