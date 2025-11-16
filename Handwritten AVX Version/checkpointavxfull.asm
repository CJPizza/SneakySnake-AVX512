
; SneakySnake.asm with IterationNo parameter
; New signature: SneakySnake(ReadLength, RefSeq, ReadSeq, EditThreshold, IterationNo)

default rel
bits 64

section .data
global SneakySnake
global global_counter
global checkpoint_base
global processed_counter
global best_diagonal_score
global main_diagonal_length
global safety_counter
global best_edit_distance
global current_batch_edits

global_counter dq 0
checkpoint_base dq 0
processed_counter dq 0
best_diagonal_score dq 0        
main_diagonal_length dq 0
safety_counter dq 0
best_edit_distance dq 999
current_batch_edits dq 0

section .rodata
align 64
four_mask:  times 64 db 0x0F
f0_mask:    times 64 db 0xF0

section .text
global SneakySnake

SneakySnake:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 32

    ; NEW PARAMETER ORDER:
    ; rdi = ReadLength
    ; rsi = RefSeq
    ; rdx = ReadSeq
    ; rcx = EditThreshold
    ; r8  = IterationNo
    
    mov     r13, rdi              ; ReadLength
    mov     r12, rsi              ; RefSeq
    mov     r11, rdx              ; ReadSeq
    mov     r10, rcx              ; EditThreshold
    mov     [rbp-8], r8           ; IterationNo (save to stack for later access)

    xor     rax, rax
    mov     [checkpoint_base], rax
    mov     [processed_counter], rax
    mov     [global_counter], rax
    mov     [best_diagonal_score], rax
    mov     [main_diagonal_length], rax
    mov     [safety_counter], rax
    mov     [current_batch_edits], rax
    
    mov     rax, 999
    mov     [best_edit_distance], rax

    mov     r15, r13
    shr     r15, 1
    
    xor     r9, r9
    
.mainloop:
    inc     qword [safety_counter]
    mov     rax, [safety_counter]
    mov     rbx, [rbp-8]          ; Load IterationNo from stack
    cmp     rax, rbx              ; Compare against IterationNo instead of hardcoded 200
    jg      .safety_exit
    
    cmp     r9, r15
    jae     .handle_tail

    xor     rax, rax
    mov     [main_diagonal_length], rax

    vmovdqu8 zmm0, [r11 + r9]
    vmovdqu8 zmm1, [r12 + r9]

    ; ========== MAIN DIAGONAL ==========
    vpandd   zmm4, zmm0, [f0_mask]
    vpandd   zmm5, zmm1, [f0_mask]
    vpcmpeqb k4, zmm4, zmm5
    
    vpandd   zmm2, zmm0, [four_mask]
    vpandd   zmm3, zmm1, [four_mask]
    vpcmpeqb k3, zmm2, zmm3
    
    knotq    k4, k4
    knotq    k3, k3
     
    korq     k5, k4, k3
    ktestq   k5, k5
    jz       .all_matched_main
    
    kmovq    rbx, k4
    tzcnt    rbx, rbx
    shl      rbx, 1

    kmovq    r8, k3
    tzcnt    r8, r8
    lea      r8, [r8*2+1]

    cmp      rbx, r8
    cmovnb   rbx, r8
    
    mov      [global_counter], rbx
    mov      [main_diagonal_length], rbx
    
    mov      rax, r9
    shl      rax, 1
    add      rax, rbx
    
    cmp      rax, r13
    jbe      .main_pos_ok
    mov      rax, r13
.main_pos_ok:
    
    mov      rcx, [best_diagonal_score]
    cmp      rax, rcx
    ja       .main_better
    jb       .skip_main_update
    
    mov      rcx, [best_edit_distance]
    mov      rdx, [current_batch_edits]
    cmp      rdx, rcx
    jae      .skip_main_update
    
.main_better:
    mov      [best_diagonal_score], rax
    mov      rdx, [current_batch_edits]
    mov      [best_edit_distance], rdx
    
.skip_main_update:
    jmp      .check_edits

.all_matched_main:
    mov      rax, r9
    shl      rax, 1
    mov      rcx, r13
    sub      rcx, rax
    
    mov      rbx, r15
    sub      rbx, r9
    shl      rbx, 1
    
    cmp      rcx, rbx
    cmova    rcx, rbx
    cmp      rcx, 128
    jbe      .cap_main
    mov      rcx, 128
.cap_main:
    
    test     rcx, rcx
    jz       .min_advance
    
    mov      [global_counter], rcx
    mov      [main_diagonal_length], rcx
    
    mov      rax, r9
    shl      rax, 1
    add      rax, rcx
    
    cmp      rax, r13
    jbe      .pos_ok_main
    mov      rax, r13
.pos_ok_main:
    
    mov      rbx, [best_diagonal_score]
    cmp      rax, rbx
    ja       .main_all_better
    jb       .skip_main_all
    
    mov      rbx, [best_edit_distance]
    mov      rdx, [current_batch_edits]
    cmp      rdx, rbx
    jae      .skip_main_all
    
.main_all_better:
    mov      [best_diagonal_score], rax
    mov      rdx, [current_batch_edits]
    mov      [best_edit_distance], rdx
    
.skip_main_all:
    jmp      .update_position

.check_edits:
    mov      r14, 1
    
    mov      rax, [main_diagonal_length]
    mov      rsi, r9
    shl      rsi, 1
    add      rsi, rax
    inc      rsi
    
.scan_loop:
    cmp      rsi, r13
    jae      .scan_complete
    
    cmp      r14, 200
    jge      .scan_stopped
    
    mov      rdi, rsi
    shr      rdi, 1
    cmp      rdi, r15
    jae      .scan_stopped
    
    movzx    eax, byte [r11 + rdi]
    movzx    ecx, byte [r12 + rdi]
    
    test     sil, 1
    jz       .scan_even
    
    and      al, 0x0F
    and      cl, 0x0F
    jmp      .scan_compare
    
.scan_even:
    shr      al, 4
    shr      cl, 4
    
.scan_compare:
    cmp      al, cl
    je       .scan_match
    
    inc      r14
    
    mov      rax, [current_batch_edits]
    add      rax, r14
    cmp      rax, r10
    jg       .scan_stopped
    
.scan_match:
    inc      rsi
    jmp      .scan_loop
    
.scan_complete:
    mov      rax, [current_batch_edits]
    add      rax, r14
    
    cmp      rax, r10
    jg       .scan_stopped
    
    mov      [best_diagonal_score], r13
    mov      [best_edit_distance], rax
    
    ; FIX: Check threshold immediately
    cmp      rax, r10
    jg       .rejected
    
    mov      rcx, r13
    mov      rdx, r9
    shl      rdx, 1
    sub      rcx, rdx
    mov      [global_counter], rcx
    
    jmp      .try_standard_diagonals
    
.scan_stopped:
    cmp      rsi, r13
    jbe      .stopped_pos_ok
    mov      rsi, r13
.stopped_pos_ok:
    
    mov      rax, [current_batch_edits]
    add      rax, r14
    
    cmp      rax, r10
    jg       .rejected
    
    mov      [best_edit_distance], rax
    
    mov      rcx, [best_diagonal_score]
    cmp      rsi, rcx
    ja       .stopped_better
    jmp      .try_standard_diagonals
    
.stopped_better:
    mov      [best_diagonal_score], rsi
    
    mov      rcx, rsi
    mov      rdx, r9
    shl      rdx, 1
    sub      rcx, rdx
    cmp      rcx, 0
    jge      .stopped_gc_ok
    xor      rcx, rcx
.stopped_gc_ok:
    mov      [global_counter], rcx
    
.try_standard_diagonals:
    mov      rax, [best_diagonal_score]
    cmp      rax, r13
    jae      .update_position
    
    mov      rdi, [current_batch_edits]
    mov      rax, r10
    sub      rax, rdi
    jle      .update_position
    
    mov      r14, rax
    vmovdqa64 zmm10, zmm4
    vmovdqa64 zmm11, zmm2
    
    xor      rdi, rdi

.edit_loop:
    inc      rdi
    cmp      rdi, r14
    jg       .update_position
    
    mov      rax, [current_batch_edits]
    add      rax, rdi
    cmp      rax, r10
    jg       .update_position
    
    mov      rbx, rdi
    shr      rbx, 1
    mov      r8d, edi
    and      r8d, 1

    ; RIGHT DIAGONAL
    cmp      r9, 0
    jne      .right_not_first
    
    cmp      r8d, 1
    je       .right_first_odd
    
    sub      rsp, 64
    xor      rsi, rsi
    
.right_first_even_pad:
    cmp      rsi, rbx
    jae      .right_first_even_data
    mov      byte [rsp + rsi], 0xFF
    inc      rsi
    jmp      .right_first_even_pad
    
.right_first_even_data:
    cmp      rsi, 64
    jae      .right_first_even_done
    mov      rax, rsi
    sub      rax, rbx
    movzx    ecx, byte [r11 + rax]
    mov      byte [rsp + rsi], cl
    inc      rsi
    jmp      .right_first_even_data
    
.right_first_even_done:
    vmovdqu8 zmm6, [rsp]
    add      rsp, 64
    jmp      .right_compare
    
.right_first_odd:
    cmp      rbx, 0
    je       .right_odd_zero
    
    sub      rsp, 64
    xor      rsi, rsi
    
.right_first_odd_pad:
    cmp      rsi, rbx
    jae      .right_first_odd_nibble
    mov      byte [rsp + rsi], 0xFF
    inc      rsi
    jmp      .right_first_odd_pad
    
.right_first_odd_nibble:
    movzx    eax, byte [r11]
    shr      eax, 4
    or       al, 0xF0
    mov      byte [rsp + rsi], al
    inc      rsi
    
.right_first_odd_data:
    cmp      rsi, 63
    jae      .right_first_odd_done
    
    mov      rax, rsi
    sub      rax, rbx
    dec      rax
    
    movzx    ecx, byte [r11 + rax]
    movzx    r8d, byte [r11 + rax + 1]
    
    and      ecx, 0x0F
    shr      r8d, 4
    and      r8d, 0x0F
    shl      ecx, 4
    or       ecx, r8d
    mov      byte [rsp + rsi], cl
    inc      rsi
    jmp      .right_first_odd_data
    
.right_first_odd_done:
    vmovdqu8 zmm6, [rsp]
    add      rsp, 64
    jmp      .right_compare
    
.right_odd_zero:
    sub      rsp, 64
    movzx    eax, byte [r11 + r9]
    shr      eax, 4
    or       al, 0xF0
    mov      byte [rsp], al
    mov      rsi, 1
    
.right_odd_zero_loop:
    cmp      rsi, 64
    jae      .right_odd_zero_done
    
    mov      rax, r9
    add      rax, rsi
    dec      rax
    
    lea      r8, [rax + 1]
    cmp      r8, r15
    jae      .right_odd_zero_last
    
    movzx    ecx, byte [r11 + rax]
    movzx    r8d, byte [r11 + rax + 1]
    
    and      ecx, 0x0F
    shr      r8d, 4
    and      r8d, 0x0F
    shl      ecx, 4
    or       ecx, r8d
    mov      byte [rsp + rsi], cl
    inc      rsi
    jmp      .right_odd_zero_loop

.right_odd_zero_last:
    movzx    ecx, byte [r11 + rax]
    and      ecx, 0x0F
    or       cl, 0xF0
    mov      byte [rsp + rsi], cl
    inc      rsi
    jmp      .right_odd_zero_loop
    
.right_odd_zero_done:
    vmovdqu8 zmm6, [rsp]
    add      rsp, 64
    jmp      .right_compare

.right_not_first:
    cmp      r9, rbx
    jb       .right_zero_fill
    
    cmp      r8d, 1
    jne      .right_even_load
    cmp      rbx, 0
    je       .right_odd_zero
    
    sub      rsp, 64
    xor      rsi, rsi
    
.right_odd_shift:
    cmp      rsi, 64
    jae      .right_odd_done
    
    mov      rax, r9
    sub      rax, rbx
    add      rax, rsi
    
    cmp      rax, r15
    jae      .right_odd_last
    
    movzx    ecx, byte [r11 + rax]
    movzx    r8d, byte [r11 + rax + 1]
    
    shr      ecx, 4
    and      ecx, 0x0F
    and      r8d, 0x0F
    shl      ecx, 4
    or       ecx, r8d
    mov      byte [rsp + rsi], cl
    inc      rsi
    jmp      .right_odd_shift

.right_odd_last:
    movzx    ecx, byte [r11 + rax]
    shr      ecx, 4
    or       cl, 0xF0
    mov      byte [rsp + rsi], cl
    inc      rsi
    jmp      .right_odd_shift
    
.right_odd_done:
    vmovdqu8 zmm6, [rsp]
    add      rsp, 64
    jmp      .right_compare
    
.right_even_load:
    mov      rax, r9
    sub      rax, rbx
    vmovdqu8 zmm6, [r11 + rax]
    jmp      .right_compare

.right_zero_fill:
    vpxord   zmm6, zmm6, zmm6
    
.right_compare:
    vpandd   zmm7, zmm6, [f0_mask]
    vpandd   zmm8, zmm6, [four_mask]
    
    vpcmpeqb k6, zmm7, zmm10
    vpcmpeqb k7, zmm8, zmm11
    
    knotq    k6, k6
    knotq    k7, k7
    
    korq     k5, k6, k7
    ktestq   k5, k5
    jz       .right_all_matched
    
    kmovq    rax, k6
    tzcnt    rax, rax
    shl      rax, 1
    
    kmovq    rcx, k7
    tzcnt    rcx, rcx
    lea      rcx, [rcx*2+1]
    
    cmp      rax, rcx
    cmovnb   rax, rcx
    
    mov      rcx, [global_counter]
    cmp      rax, rcx
    jae      .skip_right_gc
    mov      [global_counter], rax
.skip_right_gc:
    
    mov      rcx, r9
    shl      rcx, 1
    add      rcx, rax
    cmp      rcx, r13
    jbe      .right_pos_ok
    mov      rcx, r13
.right_pos_ok:
    
    mov      rax, [current_batch_edits]
    add      rax, rdi
    
    mov      rdx, [best_diagonal_score]
    cmp      rcx, rdx
    ja       .right_better
    jb       .left_diagonal
    
    mov      rdx, [best_edit_distance]
    cmp      rax, rdx
    jae      .left_diagonal
    
.right_better:
    mov      [best_diagonal_score], rcx
    mov      [best_edit_distance], rax
    
    ; FIX: Check threshold immediately
    cmp      rax, r10
    jg       .rejected
    
    jmp      .left_diagonal

.right_all_matched:
    mov      rax, r9
    shl      rax, 1
    mov      rcx, r13
    sub      rcx, rax
    
    mov      rbx, r15
    sub      rbx, r9
    shl      rbx, 1
    
    cmp      rcx, rbx
    cmova    rcx, rbx
    cmp      rcx, 128
    jbe      .right_cap
    mov      rcx, 128
.right_cap:
    
    test     rcx, rcx
    jz       .left_diagonal
    
    mov      rax, [global_counter]
    cmp      rcx, rax
    jbe      .skip_right_all_gc
    mov      [global_counter], rcx
.skip_right_all_gc:
    
    mov      rax, r9
    shl      rax, 1
    add      rax, rcx
    cmp      rax, r13
    jbe      .right_all_pos_ok
    mov      rax, r13
.right_all_pos_ok:
    
    mov      rcx, [current_batch_edits]
    add      rcx, rdi
    
    mov      rdx, [best_diagonal_score]
    cmp      rax, rdx
    ja       .right_all_better
    jb       .left_diagonal
    
    mov      rdx, [best_edit_distance]
    cmp      rcx, rdx
    jae      .left_diagonal
    
.right_all_better:
    mov      [best_diagonal_score], rax
    mov      [best_edit_distance], rcx
    
    ; FIX: Check threshold immediately
    cmp      rcx, r10
    jg       .rejected

.left_diagonal:
    lea      rax, [r9 + rbx]
    cmp      rax, r15
    jae      .left_zero_fill
    
    cmp      r8d, 0
    je       .left_even_load
    
    sub      rsp, 64
    xor      rsi, rsi
    
.left_odd_shift:
    cmp      rsi, 63
    jae      .left_odd_done
    
    lea      rax, [r9 + rbx]
    add      rax, rsi
    
    movzx    ecx, byte [r11 + rax]
    movzx    r8d, byte [r11 + rax + 1]
    
    and      ecx, 0x0F
    shr      r8d, 4
    and      r8d, 0x0F
    shl      ecx, 4
    or       ecx, r8d
    mov      byte [rsp + rsi], cl
    inc      rsi
    jmp      .left_odd_shift

.left_odd_done:
    vmovdqu8 zmm6, [rsp]
    add      rsp, 64
    jmp      .left_compare
    
.left_even_load:
    vmovdqu8 zmm6, [r11 + rax]
    jmp      .left_compare

.left_zero_fill:
    vpxord   zmm6, zmm6, zmm6
    
.left_compare:
    vpandd   zmm7, zmm6, [f0_mask]
    vpandd   zmm8, zmm6, [four_mask]
    
    vpcmpeqb k6, zmm7, zmm10
    vpcmpeqb k7, zmm8, zmm11
    
    knotq    k6, k6
    knotq    k7, k7
    
    korq     k5, k6, k7
    ktestq   k5, k5
    jz       .left_all_matched
    
    kmovq    rax, k6
    tzcnt    rax, rax
    shl      rax, 1
    
    kmovq    rcx, k7
    tzcnt    rcx, rcx
    lea      rcx, [rcx*2+1]
    
    cmp      rax, rcx
    cmovnb   rax, rcx
    
    mov      rcx, [global_counter]
    cmp      rax, rcx
    jae      .skip_left_gc
    mov      [global_counter], rax
.skip_left_gc:
    
    mov      rcx, r9
    shl      rcx, 1
    add      rcx, rax
    cmp      rcx, r13
    jbe      .left_pos_ok
    mov      rcx, r13
.left_pos_ok:
    
    mov      rax, [current_batch_edits]
    add      rax, rdi
    
    mov      rdx, [best_diagonal_score]
    cmp      rcx, rdx
    ja       .left_better
    jb       .edit_loop
    
    mov      rdx, [best_edit_distance]
    cmp      rax, rdx
    jae      .edit_loop
    
.left_better:
    mov      [best_diagonal_score], rcx
    mov      [best_edit_distance], rax
    
    ; FIX: Check threshold immediately
    cmp      rax, r10
    jg       .rejected
    
    jmp      .edit_loop

.left_all_matched:
    mov      rax, r9
    shl      rax, 1
    mov      rcx, r13
    sub      rcx, rax
    
    mov      rbx, r15
    sub      rbx, r9
    shl      rbx, 1
    
    cmp      rcx, rbx
    cmova    rcx, rbx
    cmp      rcx, 128
    jbe      .left_cap
    mov      rcx, 128
.left_cap:
    
    test     rcx, rcx
    jz       .edit_loop
    
    mov      rax, [global_counter]
    cmp      rcx, rax
    jbe      .skip_left_all_gc
    mov      [global_counter], rcx
.skip_left_all_gc:
    
    mov      rax, r9
    shl      rax, 1
    add      rax, rcx
    cmp      rax, r13
    jbe      .left_all_pos_ok
    mov      rax, r13
.left_all_pos_ok:
    
    mov      rcx, [current_batch_edits]
    add      rcx, rdi
    
    mov      rdx, [best_diagonal_score]
    cmp      rax, rdx
    ja       .left_all_better
    jb       .edit_loop
    
    mov      rdx, [best_edit_distance]
    cmp      rcx, rdx
    jae      .edit_loop
    
.left_all_better:
    mov      [best_diagonal_score], rax
    mov      [best_edit_distance], rcx
    
    ; FIX: Check threshold immediately
    cmp      rcx, r10
    jg       .rejected
    
    jmp      .edit_loop

.update_position:
    inc      qword [processed_counter]
    
    mov      rax, [global_counter]
    test     rax, rax
    jz       .min_advance
    
    cmp      rax, 128
    jbe      .advance_ok
    mov      rax, 2
.advance_ok:
    
    inc      rax
    shr      rax, 1
    add      r9, rax
    
    mov      rax, r9
    shl      rax, 1
    cmp      rax, r13
    cmova    rax, r13
    mov      [checkpoint_base], rax
    
    mov      rax, [checkpoint_base]
    mov      rbx, [best_diagonal_score]
    cmp      rax, rbx
    jbe      .update_batch_edits
    
    jmp      .mainloop
    
.update_batch_edits:
    mov      rax, [best_edit_distance]
    cmp      rax, 999
    je       .mainloop
    
    ; CRITICAL FIX: Check if best_edit_distance exceeds threshold
    cmp      rax, r10
    jg       .rejected
    
    mov      [current_batch_edits], rax
    jmp      .mainloop

.min_advance:
    inc      r9
    mov      rax, r9
    shl      rax, 1
    cmp      rax, r13
    cmova    rax, r13
    mov      [checkpoint_base], rax
    
    mov      rax, [checkpoint_base]
    mov      rbx, [best_diagonal_score]
    cmp      rax, rbx
    jbe      .min_update_batch_edits
    jmp      .mainloop
    
.min_update_batch_edits:
    mov      rax, [best_edit_distance]
    cmp      rax, 999
    je       .mainloop
    
    ; CRITICAL FIX: Check threshold here too
    cmp      rax, r10
    jg       .rejected
    
    mov      [current_batch_edits], rax
    jmp      .mainloop

.handle_tail:
    ; Check if we reached the end
    mov      rax, [best_diagonal_score]
    cmp      rax, r13
    jb       .rejected
    
    ; Check if within threshold
    mov      rbx, [best_edit_distance]
    cmp      rbx, r10
    jle      .accepted

.rejected:
    xor      rax, rax
    jmp      .end

.safety_exit:
    xor      rax, rax
    jmp      .end

.accepted:
    mov      rax, 1

.end:
    add      rsp, 32
    pop      r15
    pop      r14
    pop      r13
    pop      r12
    pop      rbx
    leave
    ret
