#include <iostream>
#include "preprocessing.h"
// nasm -f win64 avx512.asm -o sneaky.obj
// g++ sneaky.obj main.cpp -o test.exe
// test.exe

// this the assembly function
extern "C" int SneakySnake(int ReadLength, char* RefSeq, char* ReadSeq, int EditThreshold, int KmerSize, int DebugMode, int IterationNo);

int main() {
    int readLen, editThresh, kmerSize, debugMode, iterNo;
    char ref[100], read[100];

    std::cout << "Enter ReadLength: ";
    std::cin >> readLen;

    std::cout << "Enter RefSeq: ";
    std::cin >> ref;

    std::cout << "Enter ReadSeq: ";
    std::cin >> read;

    std::cout << "Enter EditThreshold: ";
    std::cin >> editThresh;

    std::cout << "Enter KmerSize: ";
    std::cin >> kmerSize;

    std::cout << "Enter DebugMode: ";
    std::cin >> debugMode;

    std::cout << "Enter IterationNo: ";
    std::cin >> iterNo;

    std::cout << "\nPassing to assembly:\n";
    std::cout << "ReadLength = " << readLen << "\n";
    std::cout << "RefSeq = " << ref << "\n";
    std::cout << "ReadSeq = " << read << "\n";
    std::cout << "EditThreshold = " << editThresh << "\n";
    std::cout << "KmerSize = " << kmerSize << "\n";
    std::cout << "DebugMode = " << debugMode << "\n";
    std::cout << "IterationNo = " << iterNo << "\n\n";

    //preprocessing
	preprocess(ref, read, readLen);

    int result = SneakySnake(readLen, ref, read, editThresh, kmerSize, debugMode, iterNo);

    std::cout << "Result from assembly = " << result << std::endl;

    return 0;
}