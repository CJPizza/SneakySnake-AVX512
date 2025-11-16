
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/time.h>
#include "preprocessing.h"

// External assembly function with new signature
extern uint64_t SneakySnake(uint64_t ReadLength, uint8_t* RefSeq, 
                             uint8_t* ReadSeq, uint64_t EditThreshold,
                             uint64_t IterationNo);

// External counters
extern uint64_t global_counter;
extern uint64_t checkpoint_base;
extern uint64_t processed_counter;
extern uint64_t best_diagonal_score;
extern uint64_t main_diagonal_length;
extern uint64_t safety_counter;
extern uint64_t best_edit_distance;
extern uint64_t current_batch_edits;

// Count actual mismatches
int count_mismatches(const char* seq1, const char* seq2, int length) {
    int count = 0;
    for (int i = 0; i < length; i++) {
        if (seq1[i] != seq2[i]) count++;
    }
    return count;
}

void print_detailed_trace(const char* read_seq, const char* ref_seq,
                         uint64_t result, int seq_num, int actual_mismatches,
                         int edit_threshold) {
 //   printf("\n========== Sequence #%d ==========\n", seq_num);
 //   printf("Read: %.50s...\n", read_seq);
 //   printf("Ref:  %.50s...\n", ref_seq);
 //   printf("Length: %lu\n", (uint64_t)strlen(read_seq));
    
    // Check if actually perfect
    int perfect = (actual_mismatches == 0);
 //   printf("\n=== ACTUAL vs REPORTED ===\n");
//    printf("Actual mismatches: %d\n", actual_mismatches);
 //   printf("Actual perfect match: %s\n", perfect ? "YES" : "NO");
 //   printf("Reported edit distance: %lu\n", best_edit_distance);
 //   printf("Match: %s\n", 
   //        (actual_mismatches == best_edit_distance) ? "✓ CORRECT" : "❌ WRONG!");
    
 //   printf("\nCheckpoint State:\n");
  //  printf("  checkpoint_base: %lu\n", checkpoint_base);
  //  printf("  best_diagonal_score: %lu\n", best_diagonal_score);
  //  printf("  current_batch_edits: %lu\n", current_batch_edits);
 //   printf("  best_edit_distance: %lu\n", best_edit_distance);
  //  printf("  processed_counter: %lu (checkpoints passed)\n", processed_counter);
  //  printf("  main_diagonal_length: %lu\n", main_diagonal_length);
  //  printf("  global_counter: %lu\n", global_counter);
  //  printf("  safety_counter: %lu\n", safety_counter);
    
   // printf("\nResult: %s\n", result ? "✓ ACCEPT" : "✗ REJECT");
    
  //  if (best_diagonal_score < strlen(read_seq)) {
 //       printf("  ⚠ Did not reach end (stopped at %lu/%lu)\n",
 //              best_diagonal_score, (uint64_t)strlen(read_seq));
  //  }
    
    // Bug detection - FIXED to respect threshold
//    if (result == 1 && actual_mismatches > edit_threshold) {
 //       printf("\n❌ BUG DETECTED: Accepted sequence with %d mismatches (threshold: %d)!\n", 
  //             actual_mismatches, edit_threshold);
 //   }
 //   if (result == 1 && best_edit_distance != actual_mismatches) {
  //      printf("\n❌ BUG: Edit distance mismatch! Reported %lu but actual is %d\n",
// best_edit_distance, actual_mismatches);
 //   }
}

void process_dataset_debug(const char* filename, int EditThreshold, 
                          int IterationNo, int limit) {
    FILE *file = fopen(filename, "r");
    if (!file) {
        printf("Error: Cannot open file %s\n", filename);
        return;
    }
    
    char line[512];
    int total_pairs = 0;
    int accepted = 0;
    int rejected = 0;
    int bug_count = 0;
    
    printf("========================================\n");
    printf("DEBUG MODE: Checking first %d sequences\n", limit);
    printf("Edit Threshold: %d\n", EditThreshold);
    printf("Max Iterations: %d\n", IterationNo);
    printf("========================================\n");
    
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
        
        // Check limit
        if (total_pairs > limit) {
            break;
        }
        
        // Count actual mismatches BEFORE preprocessing
        int actual_mismatches = count_mismatches(read_seq, ref_seq, len);
        
        // Create copies
        char* read_copy = malloc(len + 64);
        char* ref_copy = malloc(len + 64);
        char* read_orig = strdup(read_seq);
        char* ref_orig = strdup(ref_seq);
        strcpy(read_copy, read_seq);
        strcpy(ref_copy, ref_seq);
        
        // Preprocess
        preprocess(ref_copy, read_copy, len);
        
        // Reset counters
        global_counter = 0;
        checkpoint_base = 0;
        processed_counter = 0;
        best_diagonal_score = 0;
        main_diagonal_length = 0;
        safety_counter = 0;
        best_edit_distance = 999;
        current_batch_edits = 0;
        
        // Call assembly with new signature:
        // SneakySnake(ReadLength, RefSeq, ReadSeq, EditThreshold, IterationNo)
        uint64_t result = SneakySnake(len,
                                      (uint8_t*)ref_copy, 
                                      (uint8_t*)read_copy,
                                      EditThreshold,
                                      IterationNo);
        
        if (result == 1) {
            accepted++;
        } else {
            rejected++;
        }
        
        // Check for bugs - FIXED to respect threshold
        int has_bug = 0;
        if (result == 1 && actual_mismatches > EditThreshold) {
            has_bug = 1;
            bug_count++;
        }
        if (result == 1 && best_edit_distance != actual_mismatches) {
            has_bug = 1;
            bug_count++;
        }
        
        // Show ALL accepted or sequences with bugs
        if (result == 1 || has_bug) {
            print_detailed_trace(read_orig, ref_orig, result, total_pairs, 
                               actual_mismatches, EditThreshold);
        }
        
        free(read_copy);
        free(ref_copy);
        free(read_orig);
        free(ref_orig);
    }
    
    fclose(file);
    
    // Summary
    printf("\n\n========================================\n");
    printf("DEBUG SUMMARY\n");
    printf("========================================\n");
    printf("Sequences tested: %d\n", total_pairs);
    printf("Accepted: %d\n", accepted);
    printf("Rejected: %d\n", rejected);
    printf("Bugs detected: %d\n", bug_count);
    
    if (bug_count > 0) {
        printf("\n❌ BUGS FOUND! Check output above.\n");
    } else {
        printf("\n✓ No bugs detected in tested sequences.\n");
    }
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: %s <dataset_file> [edit_threshold] [iteration_no] [limit]\n", argv[0]);
        printf("Example: %s dataset.txt 0 200 100\n", argv[0]);
        printf("  Tests first 100 sequences with threshold=0, max 200 iterations\n");
        return 1;
    }
    
    const char* filename = argv[1];
    int EditThreshold = 0;     // Default to 0 for strict testing
    int IterationNo = 200;     // Default to 200 max iterations
    int limit = 100;           // Default to 100 sequences
    
    if (argc >= 3) {
        EditThreshold = atoi(argv[2]);
    }
    if (argc >= 4) {
        IterationNo = atoi(argv[3]);
    }
    if (argc >= 5) {
        limit = atoi(argv[4]);
    }
    
    process_dataset_debug(filename, EditThreshold, IterationNo, limit);
    
    return 0;
}
