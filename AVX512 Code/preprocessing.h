#ifndef PREPROCESS_H
#define PREPROCESS_H

void preprocess(char* RefSeq, char* ReadSeq, int ReadLength)
{
    int i, index = 0;

    #define ENCODE_BASE(b) \
        ((b) == 'A' || (b) == 'a' ? 0b0000 : \
         (b) == 'C' || (b) == 'c' ? 0b0001 : \
         (b) == 'G' || (b) == 'g' ? 0b0010 : \
         (b) == 'T' || (b) == 't' ? 0b0011 : \
         (b) == 'N' || (b) == 'n' ? 0b0100 : 0x0F)

    for (i = 0; i < ReadLength; i += 2) {
        unsigned char base1_r = ENCODE_BASE(ReadSeq[i]);
        unsigned char base1_f = ENCODE_BASE(RefSeq[i]);

        unsigned char base2_r = 0;             
        unsigned char base2_f = 0;

        if (i + 1 < ReadLength) {
            base2_r = ENCODE_BASE(ReadSeq[i + 1]);
            base2_f = ENCODE_BASE(RefSeq[i + 1]);
        }
        else {
            base2_r = 0x0F; // Padding for odd length
            base2_f = 0x0F; // Padding for odd length
        }

        // Pack two 4-bit bases into one byte
        ReadSeq[index] = (char)((base1_r << 4) | base2_r);
        RefSeq[index]  = (char)((base1_f << 4) | base2_f);
        index++;
    }

    #undef ENCODE_BASE
}

#endif // PREPROCESS_H
