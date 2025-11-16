
#include <immintrin.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>

uint64_t best_diagonal_score = 0;

static inline int count_consecutive_matches_avx512(char* read, char* ref, int start, int end) {
    int count = 0;
    int i = start;
    
    // Process 64 bytes at a time
    for (; i <= end - 64; i += 64) {
        __m512i read_vec = _mm512_loadu_si512((__m512i*)(read + i));
        __m512i ref_vec = _mm512_loadu_si512((__m512i*)(ref + i));
        __mmask64 cmp_mask = _mm512_cmpeq_epi8_mask(read_vec, ref_vec);
        
        if (cmp_mask == 0xFFFFFFFFFFFFFFFF) {
            count += 64;
        } else {
            count += __builtin_ctzll(~cmp_mask);
            return count;
        }
    }
    
    // Process remaining bytes
    for (; i < end; i++) {
        if (read[i] == ref[i]) {
            count++;
        } else {
            break;
        }
    }
    
    return count;
}

static inline int count_diagonal_matches_avx512(char* read, char* ref, int start, int end, int shift, int read_length, int is_right_diag) {
    int count = 0;
    int i = start;
    
    if (is_right_diag) {
        // Right diagonal (deletion)
        // read[i-shift] vs ref[i]
        for (; i <= end - 64; i += 64) {
            if (i - shift < 0) break;
            
            __m512i read_vec = _mm512_loadu_si512((__m512i*)(read + i - shift));
            __m512i ref_vec = _mm512_loadu_si512((__m512i*)(ref + i));
            __mmask64 cmp_mask = _mm512_cmpeq_epi8_mask(read_vec, ref_vec);
            
            if (cmp_mask == 0xFFFFFFFFFFFFFFFF) {
                count += 64;
            } else {
                count += __builtin_ctzll(~cmp_mask);
                return count;
            }
        }
        
        // Handle remaining bytes
        for (; i < end; i++) {
            int read_pos = i - shift;
            if (read_pos < 0) break;
            if (read[read_pos] == ref[i]) {
                count++;
            } else {
                break;
            }
        }
    } else {
        // Left diagonal (insertion)
        // read[i+shift] vs ref[i]  
        for (; i <= end - 64; i += 64) {
            if (i + shift + 64 > read_length) break;
            
            __m512i read_vec = _mm512_loadu_si512((__m512i*)(read + i + shift));
            __m512i ref_vec = _mm512_loadu_si512((__m512i*)(ref + i));
            __mmask64 cmp_mask = _mm512_cmpeq_epi8_mask(read_vec, ref_vec);
            
            if (cmp_mask == 0xFFFFFFFFFFFFFFFF) {
                count += 64;
            } else {
                count += __builtin_ctzll(~cmp_mask);
                return count;
            }
        }
        
        // Handle remaining bytes
        for (; i < end; i++) {
            int read_pos = i + shift;
            if (read_pos >= read_length) break;
            if (read[read_pos] == ref[i]) {
                count++;
            } else {
                break;
            }
        }
    }
    
    return count;
}

int SneakySnake(int EditThreshold, char* ReadSeq, char* RefSeq, int ReadLength, int IterationNo)
{
    int Edits = 0;
    
    int KmerSize = 100;
    int NumKmers = ReadLength / KmerSize;
    if (NumKmers == 0) {
        NumKmers = 1;
        KmerSize = ReadLength;
    }
    
    for (int K = 0; K < NumKmers; K++) {
        int KmerStart = K * KmerSize;
        int KmerEnd = (K < NumKmers - 1) ? (K + 1) * KmerSize : ReadLength;
        
        int index = KmerStart;
        int roundsNo = 1;
        
        while (index < KmerEnd) {
            int GlobalCount = 0;
            
            // Check main diagonal first
            GlobalCount = count_consecutive_matches_avx512(ReadSeq, RefSeq, index, KmerEnd);
            
            if (GlobalCount == (KmerEnd - index)) {
                break; // Perfect match in this segment
            }
            
            // Check diagonals within edit threshold
            for (int e = 1; e <= EditThreshold; e++) {
                int count = 0;
                
                // Right diagonal
                count = count_diagonal_matches_avx512(ReadSeq, RefSeq, index, KmerEnd, e, ReadLength, 1);
                if (count > GlobalCount) GlobalCount = count;
                if (GlobalCount == (KmerEnd - index)) break;
                
                // Left diagonal
                count = count_diagonal_matches_avx512(ReadSeq, RefSeq, index, KmerEnd, e, ReadLength, 0);
                if (count > GlobalCount) GlobalCount = count;
                if (GlobalCount == (KmerEnd - index)) break;
            }
            
            // Move index forward based on matches found
            index += GlobalCount;
            if (index < KmerEnd) {
                Edits++;
                index++;
                
                if (Edits > EditThreshold) {
                    best_diagonal_score = Edits;
                    return 0; // Rejected
                }
            }
            
            if (roundsNo++ > IterationNo) break;
        }
        
        if (Edits > EditThreshold) {
            best_diagonal_score = Edits;
            return 0; // Rejected
        }
    }
    
    best_diagonal_score = Edits;
    return 1; // Accepted
}
