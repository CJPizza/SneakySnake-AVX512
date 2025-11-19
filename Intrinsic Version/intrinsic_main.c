
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <sys/time.h>

// External declarations from intrinsic.c
extern int SneakySnake(int EditThreshold, char* ReadSeq, char* RefSeq, int ReadLength, int KmerSize, int IterationNo);
extern uint64_t best_diagonal_score;

typedef struct {
    char* read_seq;
    char* ref_seq;
    int length;
} SequencePair;

int read_sequences_from_file(const char* filename, SequencePair** pairs, int* count) {
    FILE* fp = fopen(filename, "r");
    if (!fp) {
        fprintf(stderr, "Error opening file: %s\n", filename);
        return -1;
    }

    // Count lines first
    int lines = 0;
    char ch;
    while ((ch = fgetc(fp)) != EOF) {
        if (ch == '\n') lines++;
    }
    
    *count = lines;
    *pairs = (SequencePair*)malloc(sizeof(SequencePair) * (*count));
    
    rewind(fp);
    
    char line[1024];
    int pair_idx = 0;
    
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\r\n")] = 0;
        
        // Try both tab and space separators
        char *separator = strchr(line, '\t');
        if (!separator) {
            separator = strchr(line, ' ');
        }
        
        if (!separator) {
            // Skip lines without separators
            continue;
        }
        
        *separator = '\0';
        char *read = line;
        char *ref = separator + 1;
        
        int len = strlen(read);
        (*pairs)[pair_idx].length = len;
        (*pairs)[pair_idx].read_seq = (char*)malloc(len + 1);
        (*pairs)[pair_idx].ref_seq = (char*)malloc(len + 1);
        strcpy((*pairs)[pair_idx].read_seq, read);
        strcpy((*pairs)[pair_idx].ref_seq, ref);
        
        pair_idx++;
    }
    
    fclose(fp);
    *count = pair_idx;
    return 0;
}

int main(int argc, char* argv[]) {
    if (argc < 3) {
        fprintf(stderr, "Usage: %s <input_file> <edit_threshold> [KmerSize] [IterationNo]\n", argv[0]);
        fprintf(stderr, "  input_file: File with read/ref pairs (one pair per line, tab/space separated)\n");
        fprintf(stderr, "  edit_threshold: Maximum edit distance to check\n");
        fprintf(stderr, "  KmerSize: Optional kmer size (default: 100)\n");
        fprintf(stderr, "  IterationNo: Optional iterations (default: 100)\n");
        return 1;
    }

    const char* input_file = argv[1];
    int EditThreshold = atoi(argv[2]);
    int KmerSize;
    int IterationNo;
    
    if (argc >= 4) KmerSize = atoi(argv[3]);
    if (argc >= 5) IterationNo = atoi(argv[4]);

    SequencePair* pairs = NULL;
    int pair_count = 0;

    if (read_sequences_from_file(input_file, &pairs, &pair_count) != 0) {
        return 1;
    }

    printf("Loaded %d sequence pairs from %s\n", pair_count, input_file);
    printf("Edit Threshold: %d, KmerSize: %d, IterationNo: %d\n", EditThreshold, KmerSize, IterationNo);

    int total_accepted = 0;
    int total_rejected = 0;

    // Start timing
    struct timeval start_time, end_time;
    gettimeofday(&start_time, NULL);

    // Process each pair - NOW PASSING ALL PARAMETERS CORRECTLY
    for (int i = 0; i < pair_count; i++) {
        char* ReadSeq = strdup(pairs[i].read_seq);
        char* RefSeq = strdup(pairs[i].ref_seq);
        int len = pairs[i].length;

        // Pass all parameters: EditThreshold, ReadSeq, RefSeq, ReadLength, KmerSize, IterationNo
        int result = SneakySnake(EditThreshold, ReadSeq, RefSeq, len, KmerSize, IterationNo);

        if (result) {
            total_accepted++;
        } else {
            total_rejected++;
        }

        free(ReadSeq);
        free(RefSeq);
    }

    // End timing
    gettimeofday(&end_time, NULL);
    long elapsed_ms = (end_time.tv_sec - start_time.tv_sec) * 1000 + 
                      (end_time.tv_usec - start_time.tv_usec) / 1000;

    printf("\nResults:\n");
    printf("  Total pairs: %d\n", pair_count);
    printf("  Accepted: %d\n", total_accepted);
    printf("  Rejected: %d\n", total_rejected);
    printf("  Time: %ld milliseconds\n", elapsed_ms);
    
    // Cleanup
    for (int i = 0; i < pair_count; i++) {
        free(pairs[i].read_seq);
        free(pairs[i].ref_seq);
    }
    free(pairs);

    return 0;
}
