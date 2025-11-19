
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/time.h>
#include "preprocessing.h"

// External assembly function
extern uint64_t SneakySnake(uint64_t ReadLength, uint8_t* RefSeq, 
                             uint8_t* ReadSeq, uint64_t EditThreshold,
                             uint64_t IterationNo);

extern uint64_t current_position;
extern uint64_t current_edits;
extern uint64_t mismatch_count;
extern uint64_t safety_counter;

double get_time() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (tv.tv_sec * 1000.0) + (tv.tv_usec / 1000.0);
}

// calculate edit distance (levenshtein distance)
int calculate_edit_distance(const char* s1, const char* s2, int len) {
    int dp[len+1][len+1];
    
    for (int i = 0; i <= len; i++) {
        dp[i][0] = i;
        dp[0][i] = i;
    }
    
    for (int i = 1; i <= len; i++) {
        for (int j = 1; j <= len; j++) {
            if (s1[i-1] == s2[j-1]) {
                dp[i][j] = dp[i-1][j-1];
            } else {
                int substitute = dp[i-1][j-1] + 1;
                int insert = dp[i][j-1] + 1;
                int delete = dp[i-1][j] + 1;
                dp[i][j] = substitute;
                if (insert < dp[i][j]) dp[i][j] = insert;
                if (delete < dp[i][j]) dp[i][j] = delete;
            }
        }
    }
    
    return dp[len][len];
}

void process_dataset(const char* filename, int EditThreshold, 
                     int IterationNo, int limit, int verbose) {
    FILE *file = fopen(filename, "r");
    if (!file) {
        printf("Error: Cannot open file %s\n", filename);
        return;
    }
    
    double start_time = get_time();
    double assembly_time = 0.0;
    double preprocessing_time = 0.0;
    double validation_time = 0.0;
    
    char line[512];
    int total_pairs = 0;
    int accepted = 0;
    int rejected = 0;
    int bug_count = 0;
    int correct_accepts = 0;
    int correct_rejects = 0;
    int false_rejects = 0;
    int false_accepts = 0;
    
    while (fgets(line, sizeof(line), file)) {
        line[strcspn(line, "\r\n")] = 0;
        
        if (strlen(line) == 0 || line[0] == '#') {
            continue;
        }
        
        char *read_seq = line;
        char *ref_seq = NULL;
        
        char *tab_pos = strchr(line, '\t');
        if (tab_pos) {
            *tab_pos = '\0';
            ref_seq = tab_pos + 1;
        } else {
            char *space_pos = strchr(line, ' ');
            if (space_pos) {
                *space_pos = '\0';
                ref_seq = space_pos + 1;
            }
        }
        
        if (!ref_seq) continue;
        
        int len = strlen(read_seq);
        if (strlen(ref_seq) != len || len > 128 || len == 0) {
            continue;
        }
        
        total_pairs++;
        if (limit > 0 && total_pairs > limit) {
            break;
        }
        
        // time validation (edit distance calculation)
        double val_start = get_time();
        int actual_edit_distance = calculate_edit_distance(read_seq, ref_seq, len);
        validation_time += (get_time() - val_start);
        
        // create copies
        char* read_copy = malloc(len + 64);
        char* ref_copy = malloc(len + 64);
        strcpy(read_copy, read_seq);
        strcpy(ref_copy, ref_seq);
        
        // time preprocessing
        double prep_start = get_time();
        preprocess(ref_copy, read_copy, len);
        preprocessing_time += (get_time() - prep_start);
        
        // reset counters
        current_position = 0;
        current_edits = 0;
        mismatch_count = 0;
        safety_counter = 0;
        
        // time assembly execution
        double asm_start = get_time();
        uint64_t result = SneakySnake(len,
                                      (uint8_t*)ref_copy, 
                                      (uint8_t*)read_copy,
                                      EditThreshold,
                                      IterationNo);
        assembly_time += (get_time() - asm_start);
        
        if (result == 1) {
            accepted++;
        } else {
            rejected++;
        }
        
        // check for bugs
        int should_accept = (actual_edit_distance <= EditThreshold);
        
        if (result == 1 && actual_edit_distance > EditThreshold) {
            bug_count++;
            false_accepts++;
            if (verbose) {
                printf("FALSE ACCEPT #%d: edit_dist=%d > threshold=%d, reported_edits=%lu\n",
                       total_pairs, actual_edit_distance, EditThreshold, current_edits);
            }
        } else if (result == 0 && actual_edit_distance <= EditThreshold) {
            bug_count++;
            false_rejects++;
            if (verbose) {
                printf("FALSE REJECT #%d: edit_dist=%d <= threshold=%d, reported_edits=%lu, pos=%lu, safety=%lu\n",
                       total_pairs, actual_edit_distance, EditThreshold, current_edits, 
                       current_position, safety_counter);
            }
        } else {
            if (result == 1 && should_accept) correct_accepts++;
            if (result == 0 && !should_accept) correct_rejects++;
        }
        
        free(read_copy);
        free(ref_copy);
        
        // progress indicator every 1000 sequences
        if (total_pairs % 1000 == 0) {
            printf("Processed %d sequences...\r", total_pairs);
            fflush(stdout);
        }
    }
    
    fclose(file);
    
    double total_time = get_time() - start_time;
    
    // summary
    printf("\n========================================\n");
    printf("SUMMARY (Threshold: %d)\n", EditThreshold);
    printf("========================================\n");
    printf("Total sequences: %d\n", total_pairs);
    printf("Accepted: %d\n", accepted);
    printf("Rejected: %d\n", rejected);
    
    // timing breakdown
    printf("\n========================================\n");
    printf("PERFORMANCE BREAKDOWN\n");
    printf("========================================\n");
    printf("Total time:         %.3f ms\n\n", total_time);

}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: %s <dataset_file> [edit_threshold] [iteration_no] [limit] [verbose]\n", argv[0]);
        printf("Example: %s dataset.txt 10 0 30000 0\n", argv[0]);
        printf("  Tests sequences with threshold=10, shows summary only\n");
        return 1;
    }
    
    const char* filename = argv[1];
    int EditThreshold = 10;
    int IterationNo = 0;      
    int limit = 30000;
    int verbose = 0;
    
    if (argc >= 3) EditThreshold = atoi(argv[2]);
    if (argc >= 4) IterationNo = atoi(argv[3]);
    if (argc >= 5) limit = atoi(argv[4]);
    if (argc >= 6) verbose = atoi(argv[5]);
    
    printf("Starting benchmark...\n");
    printf("Dataset: %s\n", filename);
    printf("Edit threshold: %d\n", EditThreshold);
    printf("Sequence limit: %d\n\n", limit);
    
    process_dataset(filename, EditThreshold, IterationNo, limit, verbose);
    
    return 0;
}
