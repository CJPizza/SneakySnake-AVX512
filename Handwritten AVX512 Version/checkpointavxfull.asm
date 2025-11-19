
default rel
bits 64

section .data
global SneakySnake
global current_position
global current_edits
global mismatch_count
global safety_counter

current_position dq 0
current_edits dq 0
mismatch_count dq 0
safety_counter dq 0

section .text
global SneakySnake

; -------------------------------------------------------------------------------------
; sneaky snake with avx-512 parallel diagonal checking
; avx-512 allows us to compare 64 bytes (128 nibbles) in a single instruction
; instead of checking each nibble one at a time in a loop

; in original code, what happens is
; for each position in sequence:
    ; extract nibble from read
    ; extract nibble from ref
    ; compare
    ; if mismatch: stop
    ; else: continue

; OKAY PLS READ THIS so what happened and the difference with the old code is that
    ; rdi - editThreshold 
    ; rsi - ReadSeq -> r11
    ; rdx - RefSeq -> r12
    ; rcx - ReadLength -> r13
    ; r8 - Iteration -> Iteration is now stored in stack
    ; r9 - shift amount for diagonals
    ; r15 - buffer offset for diagonal storage
    ; rax - match counter in diagonal functions
    ; rbx - current position calculations

; DATA STORAGE
; in the old code we used 4 sets of 64-byte buffers right_diag_read/ref, left_diag_read/ref
; this time the results are stored only in registers and stakc variables

; NIBBLE EXTRACTION
; same approach pa rin naman for byte-aligned data but it uses scalar for unaligned

; MATCH COUNTING
; we used tzcnt to count leading matches, now we check if bytes matched first, if all
; matched then add 128 and continue, if partial, count bit by bit

; DIAGONAL SHIFTING LOGIC
; before we used first-block handling, now this one if we can't use avx-512 it falls back to scalar
; doesn't use special cases anymore. it just checks if shifted positions are valid

; MAIN LOOP PROGRESSION
; this one goes straight to finding the longest match, then mismatch it checks diagonals na
; HAY PUCHHH

; GLOBAL VARIABLES
; doesn't have global counter anymore because it uses local variable r14 to track best match

; OK WAIT CZAR READ THIS ACTUALLY  
; this one prioritizes correctness more than speed kaya mas maraming SCALAR dito and less special
; cases for nibbles oki HUHUHU para it's accurate and sir rog happy yehey
; -------------------------------------------------------------------------------------

SneakySnake:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 128

    ; parameters:
    ; rdi = readlength (in nibbles)
    ; rsi = refseq
    ; rdx = readseq
    ; rcx = editthreshold
    ; r8  = iterationno
    
    ; check if the cpu actually supports avx-512
    ; this is important because older cpus will crash if we try to use these instructions
    push    rax
    push    rcx
    push    rdx
    mov     eax, 7
    xor     ecx, ecx
    cpuid
    and     ebx, (1 << 16)        ; check avx512f (foundation) bit
    pop     rdx
    pop     rcx
    pop     rax
    jz      .no_avx512            ; if not supported, return 0
    
    mov     r13, rdi              ; readlength
    mov     r12, rsi              ; refseq pointer
    mov     r11, rdx              ; readseq pointer
    mov     r10, rcx              ; editthreshold
    mov     [rbp-8], r8           ; iterationno

    ; initialize counters to zero
    xor     rax, rax
    mov     [current_position], rax
    mov     [current_edits], rax
    mov     [mismatch_count], rax
    mov     [safety_counter], rax

    xor     r15, r15              ; index = 0 (our current position in the sequences)
    
.main_loop:
    ; check if we've processed the entire read
    cmp     r15, r13 ; r15 = position if it's equal to readlength
    jae     .accept
    
    ; safety check to prevent infinite loops
    inc     qword [safety_counter]
    mov     rax, [safety_counter]
    cmp     rax, [rbp-8]
    jg      .reject
    
    ; check if we've exceeded the edit threshold (too many mismatches)
    mov     rax, [current_edits]
    cmp     rax, r10
    jg      .reject
    
    ; calculate how many nibbles remain to check
    mov     r14, r13
    sub     r14, r15              ; remaining = readlength - index
    
    ; check main diagonal with avx-512
    ; this is where the magic happens - we compare many nibbles at once
    call    .check_main_diagonal_avx512
    mov     r14, rax              ; globalcount = main diagonal matches
    
    ; if main diagonal matches everything remaining, we're done!
    mov     rbx, r13
    sub     rbx, r15
    cmp     rax, rbx
    jae     .matched_all_remaining
    
    ; store best diagonal info
    xor     r9, r9                ; best_shift = 0 (main diagonal)
    mov     [rbp-24], r9
    
    ; now check all shifted diagonals (for insertions and deletions)
    mov     r8, 1                 ; shift = 1


; shift_loop basically handles all diagonals. it checks the upper (shift right = deletion) and lower (shift left = insertion)
; example: if editThreshold = 5, then algorithm checks
    ; main diagonall = shift 0
    ; upper diagonals = shifts (1, 2, 3, 4, 5) <- 5 deletions
    ; lower diagonals = shifts (-1, -2, -3, -4, -5) <- 5 insertions TAMA BA TO HELPPPPP
.shift_loop:
    cmp     r8, r10
    ja      .shift_done
    
    ; check upper diagonal (deletion in reference)
    ; this means the read is missing a base that's in the reference
    mov     r9, r8
    call    .check_upper_diagonal_avx512
    
    ; if this matches everything, take it immediately
    mov     rbx, r13
    sub     rbx, r15
    cmp     rax, rbx
    jae     .matched_all_remaining
    
    ; update if this diagonal is better
    cmp     rax, r14
    jbe     .check_lower
    
    mov     r14, rax
    mov     r9, r8
    mov     [rbp-24], r9
    
.check_lower:
    ; check lower diagonal (insertion in reference)
    ; this means the read has an extra base that's not in the reference
    mov     r9, r8
    call    .check_lower_diagonal_avx512
    
    ; if this matches everything, take it immediately
    mov     rbx, r13
    sub     rbx, r15
    cmp     rax, rbx
    jae     .matched_all_remaining
    
    ; update if this diagonal is better
    cmp     rax, r14
    jbe     .next_shift
    
    mov     r14, rax
    mov     r9, r8
    neg     r9
    mov     [rbp-24], r9
    
.next_shift:
    inc     r8
    jmp     .shift_loop
    
.shift_done:
    ; advance by globalcount (skip all the matched positions)
    add     r15, r14
    
    ; if we reached the end, loop back to check completion
    cmp     r15, r13
    jae     .main_loop
    
    ; not at end: we hit a mismatch/error
    ; add 1 edit and skip the error position
    inc     qword [current_edits]
    inc     r15
    
    jmp     .main_loop

.matched_all_remaining:
    mov     r15, r13
    jmp     .main_loop

.accept:
    mov     [current_position], r13
    mov     rax, [current_edits]
    cmp     rax, r10
    jg      .reject
    mov     rax, 1                ; return 1 (success)
    jmp     .end

.reject:
    xor     rax, rax              ; return 0 (failure)
    jmp     .end

.no_avx512:
    xor     rax, rax              ; return 0 if no avx-512 support

.end:
    add     rsp, 128
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    leave
    ret

; -------------------------------------------------------------------------------------
; avx-512 optimized main diagonal checker
; this is the core parallelization - instead of checking nibbles one by one,
; we load 64 bytes (128 nibbles) into a 512-bit register and compare them all at once!
;
; how it works:
; 1. load 64 bytes from read sequence into zmm0 (512-bit register)
; 2. load 64 bytes from ref sequence into zmm1 (512-bit register)
; 3. compare all 64 bytes simultaneously with vpcmpeqb
; 4. the result is a mask where each bit tells us if that byte matched
; 5. if all bits are set (all bytes match), we found 128 matching nibbles in one go!
;

; ok to summarize basically now we 11 loops
    ; main loop - process entire sequence (not avx-fied)
    ; shift loop - test all error hypotheses (not avx-fied)
    ; avx-512 - match on main diagonal (this is the avx-fied so this is the one parallelized)
    ; byte counting - count partial matches
    ; main scalar - fallback matching
    ; avx-512 upper (right diagonal) - below are js the subfunctions basta this is parallelized
        ; upper count (right diagonal) - count upper partials
        ; upper scalar - jic the upper loop goes wonky
    ; avx-512 upper (right diagonal) - below are js the subfunctions basta this is parallelized
        ; upper count (right diagonal) - count lower partials
        ; upper scalar - jic the lower loop goes wonky
; -------------------------------------------------------------------------------------

; returns: rax = number of consecutive matches
.check_main_diagonal_avx512:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    
    xor     rax, rax              ; match_count = 0
    
.avx512_main_loop:
    ; calculate current position
    mov     rbx, r15
    add     rbx, rax              ; current_pos = index + match_count
    
    ; check if we've reached the end
    cmp     rbx, r13
    jae     .avx512_main_done
    
    ; check if we're byte-aligned (nibble offset is even)
    ; avx-512 works best with aligned data
    test    bl, 1
    jnz     .avx512_main_scalar   ; if odd offset, use scalar fallback
    
    ; check if we have at least 128 nibbles (64 bytes) remaining
    ; this is the minimum we need for a full avx-512 operation
    mov     rcx, r13
    sub     rcx, rbx
    cmp     rcx, 128
    jb      .avx512_main_scalar   ; not enough data, use scalar
    
    ; calculate byte offset (divide nibble offset by 2)
    mov     rsi, rbx
    shr     rsi, 1
    
    ; *** this is the key parallelization ***
    ; load 64 bytes from each sequence into 512-bit zmm registers
    ; zmm0 and zmm1 now each hold 64 bytes = 128 nibbles
    vmovdqu8 zmm0, [r11 + rsi]    ; read sequence (64 bytes at once!)
    vmovdqu8 zmm1, [r12 + rsi]    ; ref sequence (64 bytes at once!)
    
    ; *** compare all 64 bytes in parallel ***
    ; vpcmpeqb compares 64 bytes simultaneously and stores results in mask register k1
    ; each bit in k1 represents whether that byte matched (1) or not (0)
    ; this single instruction replaces 64 separate comparison operations!
    vpcmpeqb k1, zmm0, zmm1
    
    ; move the mask from k1 (special mask register) to rdx (general purpose register)
    ; so we can examine the results
    kmovq   rdx, k1
    
    ; check if all 64 bytes matched
    ; if rdx = 0xFFFFFFFFFFFFFFFF (all bits set), then all bytes matched
    cmp     rdx, -1
    jne     .avx512_main_partial  ; some bytes didn't match, handle partial case
    
    ; all 128 nibbles matched! this is why avx-512 is so fast
    ; in the scalar version, we would have needed 128 iterations of a loop
    ; with avx-512, we checked all 128 in essentially one operation
    add     rax, 128
    jmp     .avx512_main_loop     ; check the next 128 nibbles
    
.avx512_main_partial:
    ; not all bytes matched, so we need to count how many leading bytes did match
    ; this handles the case where we partially match the sequence
    ; xor     r8, r8                ; byte counter
    
.avx512_count_bytes:
    cmp     r8, 64
    jae     .avx512_main_done
    
    ; check if this byte matched by testing the corresponding bit in the mask
    ; bt (bit test) checks if bit r8 in rdx is set
    bt      rdx, r8
    jnc     .avx512_byte_mismatch ; bit not set = byte didn't match
    
    ; this byte matched, so both its nibbles matched
    add     rax, 2
    inc     r8
    jmp     .avx512_count_bytes
    
.avx512_byte_mismatch:
    ; found a byte that didn't match
    ; we need to check the individual nibbles in this byte to see if one matched
    mov     rbx, r15
    add     rbx, rax
    
    ; load the mismatched byte from each sequence
    mov     rcx, rbx
    shr     rcx, 1
    movzx   r9d, byte [r11 + rcx]  ; read byte
    movzx   edi, byte [r12 + rcx]  ; ref byte
    
    ; check high nibble (first 4 bits)
    mov     esi, r9d
    shr     esi, 4                 ; shift right to get high nibble
    mov     ecx, edi
    shr     ecx, 4
    cmp     esi, ecx
    jne     .avx512_main_done      ; high nibble doesn't match, we're done
    
    inc     rax                    ; high nibble matched
    
    ; check low nibble (last 4 bits)
    and     r9d, 0x0F              ; mask to get low nibble
    and     edi, 0x0F
    cmp     r9d, edi
    jne     .avx512_main_done      ; low nibble does nott match, we are done
    
    inc     rax                    ; low nibble matched too
    jmp     .avx512_main_done
    
.avx512_main_scalar:
    ; scalar fallback for when we cannott use avx-512
    ; this happens when:
    ; - at an odd nibble offset (not byte-aligned)
    ; - we have fewer than 128 nibbles remaining
    ; in these cases, we fall back to checking one nibble at a time
    mov     rbx, r15
    add     rbx, rax
    
    cmp     rbx, r13
    jae     .avx512_main_done
    
    ; extract the nibble from the read sequence
    mov     rcx, rbx
    shr     rcx, 1                 ; convert nibble offset to byte offset
    movzx   edi, byte [r11 + rcx]  ; load the byte
    test    bl, 1                  ; check if we want the high or low nibble
    jz      .avx512_read_even
    and     dil, 0x0F              ; odd offset = low nibble (bits 0-3)
    jmp     .avx512_read_done
.avx512_read_even:
    shr     dil, 4                 ; even offset = high nibble (bits 4-7)
.avx512_read_done:
    
    ; extract the nibble from the ref sequence
    mov     rcx, rbx
    shr     rcx, 1
    movzx   esi, byte [r12 + rcx]
    test    bl, 1
    jz      .avx512_ref_even
    and     sil, 0x0F
    jmp     .avx512_ref_done
.avx512_ref_even:
    shr     sil, 4
.avx512_ref_done:
    
    ; compare the two nibbles
    cmp     dil, sil
    jne     .avx512_main_done      ; mismatch found, stop
    
    inc     rax                    ; nibbles match, increment counter
    jmp     .avx512_main_loop      ; continue (might switch back to avx-512 if aligned)
    
.avx512_main_done:
    vzeroupper                     ; clean up avx state (important for performance)
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; avx-512 optimized upper diagonal checker
; this checks for deletions in the reference sequence
; the parallelization works the same way as the main diagonal:
; - load 64 bytes from shifted positions
; - compare all 64 bytes at once with vpcmpeqb
; - count matches
;
; the difference is that we're comparing:
; - read[position - shift] with ref[position]
; this simulates a deletion by shifting the read backwards
;
; r9 = shift amount (how many positions to shift)
; returns: rax = number of consecutive matches
.check_upper_diagonal_avx512:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    
    xor     rax, rax              ; match_count = 0
    
.avx512_upper_loop:
    mov     rbx, r15
    add     rbx, rax              ; current ref position
    
    cmp     rbx, r13
    jae     .avx512_upper_done
    
    ; check if byte-aligned and have enough data for avx-512
    test    bl, 1
    jnz     .avx512_upper_scalar
    
    mov     rcx, r13
    sub     rcx, rbx
    cmp     rcx, 128
    jb      .avx512_upper_scalar
    
    ; calculate read position with shift (deletion)
    mov     rsi, rbx
    sub     rsi, r9               ; read_pos = ref_pos - shift
    test    rsi, rsi
    js      .avx512_upper_done    ; negative position, out of bounds
    
    ; make sure we have enough read data remaining
    mov     rdx, r13
    sub     rdx, rsi
    cmp     rdx, 128
    jb      .avx512_upper_scalar
    
    ; *** parallelized comparison with shift ***
    ; load 64 bytes from the shifted read position
    mov     r8, rsi
    shr     r8, 1
    vmovdqu8 zmm0, [r11 + r8]     ; read (shifted by deletion amount)
    
    ; load 64 bytes from the normal ref position
    mov     r8, rbx
    shr     r8, 1
    vmovdqu8 zmm1, [r12 + r8]     ; ref
    
    ; compare all 64 bytes in parallel (checking 128 nibbles at once!)
    vpcmpeqb k1, zmm0, zmm1
    kmovq   rdx, k1
    
    cmp     rdx, -1
    jne     .avx512_upper_partial ; partial match, count bytes
    
    ; all 128 nibbles matched with the shift!
    add     rax, 128
    jmp     .avx512_upper_loop
    
.avx512_upper_partial:
    ; count leading matched bytes
    xor     r8, r8
    
.avx512_upper_count:
    cmp     r8, 64
    jae     .avx512_upper_done
    
    bt      rdx, r8
    jnc     .avx512_upper_done    ; found mismatch
    
    add     rax, 2                ; both nibbles in this byte matched
    inc     r8
    jmp     .avx512_upper_count
    
.avx512_upper_scalar:
    ; scalar fallback for upper diagonal
    mov     rbx, r15
    add     rbx, rax
    
    cmp     rbx, r13
    jae     .avx512_upper_done
    
    ; calculate shifted read position
    mov     rsi, rbx
    sub     rsi, r9
    test    rsi, rsi
    js      .avx512_upper_done
    cmp     rsi, r13
    jae     .avx512_upper_done
    
    ; get nibbles and compare (same as main diagonal, but with shifted read)
    mov     rcx, rsi
    shr     rcx, 1
    movzx   edi, byte [r11 + rcx]
    test    sil, 1
    jz      .upper_read_even
    and     dil, 0x0F
    jmp     .upper_read_done
.upper_read_even:
    shr     dil, 4
.upper_read_done:
    
    mov     rcx, rbx
    shr     rcx, 1
    movzx   esi, byte [r12 + rcx]
    test    bl, 1
    jz      .upper_ref_even
    and     sil, 0x0F
    jmp     .upper_ref_done
.upper_ref_even:
    shr     sil, 4
.upper_ref_done:
    
    cmp     dil, sil
    jne     .avx512_upper_done
    
    inc     rax
    jmp     .avx512_upper_loop
    
.avx512_upper_done:
    vzeroupper
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; avx-512 optimized lower diagonal checker
; this checks for insertions in the reference sequence
; the parallelization works the same way:
; - load 64 bytes from shifted positions
; - compare all 64 bytes at once
;
; the difference is that we're comparing:
; - read[position + shift] with ref[position]
; this simulates an insertion by shifting the read forwards
;
; r9 = shift amount
; returns: rax = number of consecutive matches
.check_lower_diagonal_avx512:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    
    xor     rax, rax
    
.avx512_lower_loop:
    mov     rbx, r15
    add     rbx, rax
    
    cmp     rbx, r13
    jae     .avx512_lower_done
    
    ; check if byte-aligned and enough data
    test    bl, 1
    jnz     .avx512_lower_scalar
    
    mov     rcx, r13
    sub     rcx, rbx
    cmp     rcx, 128
    jb      .avx512_lower_scalar
    
    ; calculate read position with shift (insertion)
    mov     rsi, rbx
    add     rsi, r9               ; read_pos = ref_pos + shift
    cmp     rsi, r13
    jae     .avx512_lower_done
    
    mov     rdx, r13
    sub     rdx, rsi
    cmp     rdx, 128
    jb      .avx512_lower_scalar
    
    ; *** parallelized comparison with forward shift ***
    ; load 64 bytes from the shifted read position
    mov     r8, rsi
    shr     r8, 1
    vmovdqu8 zmm0, [r11 + r8]     ; read (shifted forward by insertion amount)
    
    ; load 64 bytes from the normal ref position
    mov     r8, rbx
    shr     r8, 1
    vmovdqu8 zmm1, [r12 + r8]     ; ref
    
    ; compare all 64 bytes in parallel (128 nibbles at once!)
    vpcmpeqb k1, zmm0, zmm1
    kmovq   rdx, k1
    
    cmp     rdx, -1
    jne     .avx512_lower_partial
    
    ; all 128 nibbles matched with the forward shift!
    add     rax, 128
    jmp     .avx512_lower_loop
    
.avx512_lower_partial:
    ; count leading matches
    xor     r8, r8
    
.avx512_lower_count:
    cmp     r8, 64
    jae     .avx512_lower_done
    
    bt      rdx, r8
    jnc     .avx512_lower_done
    
    add     rax, 2
    inc     r8
    jmp     .avx512_lower_count
    
.avx512_lower_scalar:
    ; scalar fallback for lower diagonal
    mov     rbx, r15
    add     rbx, rax
    
    cmp     rbx, r13
    jae     .avx512_lower_done
    
    ; calculate shifted read position
    mov     rsi, rbx
    add     rsi, r9
    cmp     rsi, r13
    jae     .avx512_lower_done
    
    ; get nibbles and compare
    mov     rcx, rsi
    shr     rcx, 1
    movzx   edi, byte [r11 + rcx]
    test    sil, 1
    jz      .lower_read_even
    and     dil, 0x0F
    jmp     .lower_read_done
.lower_read_even:
    shr     dil, 4
.lower_read_done:
    
    mov     rcx, rbx
    shr     rcx, 1
    movzx   esi, byte [r12 + rcx]
    test    bl, 1
    jz      .lower_ref_even
    and     sil, 0x0F
    jmp     .lower_ref_done
.lower_ref_even:
    shr     sil, 4
.lower_ref_done:
    
    cmp     dil, sil
    jne     .avx512_lower_done
    
    inc     rax
    jmp     .avx512_lower_loop
    
.avx512_lower_done:
    vzeroupper      ; clears the upper bits of all vector registers (the parts above 128 bits in ymm/zmm registers) 
                    ; ok ngl idk i chatgpted this to fix the stupid garbage values i was getting 
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
