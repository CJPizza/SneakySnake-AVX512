%include "io.inc"

section .text
default rel
bits 64

section .data
 processed_counter dq 0		; this just for counting how many sequences have been processed
 accepted dq 0				; for counting how many sequences have been accepted
 rejected dq 0				; for counting how many sequences have been rejected
 read_bytes dq 0			; for counting how many bytes have been read (for the loop)
 global_count dq 0

global SneakySnake
global main

; the main prototype:
; int SneakySnake(int ReadLength, char* ReadSeq, char* RefSeq, int EditThreshold, int IterationNo)
; parameters and their corresponding registers (I AM NOT ENTIRELY SURE WITH THIS):
; int ReadLength =		rcx
; char* ReadSeq =		rdx
; char* RefSeq =		r8
; int EditThreshold =	r9
; int IterationNo =		[rbp + 8] 
; return value =		r/eax

Sneakynake:
	push rbp
	mov rbp, rsp

	push rdi			; save parameters
	push rsi			; dont know if we need these for the project, just in case lang
	push rdx
	push r12
	push r13
	push r14
	push r15
	push rbx

	;sub rsp, 32			; shadow space -- remove this cuz we r callee

	; saving arguments into registers that we wont overwrite
	mov r11, rcx			; ReadLength
	mov r12, rdx			; ReadSeq
	mov r13, r8				; RefSeq
	mov r14, r9				; EditThreshold
	mov r15, [rbp + 40h]	; IterationNo

	; r11 = ReadLength
	; r12 = ReadSeq
	; r13 = RefSeq
	; r14 = EditThreshold
	; r15 = IterationNo


	;xor stuff here


	; computing byte length of the read
	; since 8 bits is the smallest can we can work on
	; we need to divide the read length by 2 since we're working on 4-bit nucleotides
	mov rdx, r11		
	shr rdx, 1				; divides readlength by 2
	mov qword [read_bytes], rdx

	; pointers and counters
	xor rdx, rdx				; index for the read
	xor r9, r9					; offset for bytes
	xor r10, r10				; counter for mismatches
	xor rbx, rbx				; counter for matches

.mainloop:
	; main loop where we compare the read to the reference
	mov rcx, [read_bytes]	; rcx = 50
	cmp r9, rcx				; compare offset with read bytes
	jae .handle_tail		; if its false, continue the mainloop

	;get remainder -- process boundary last

	; ADDED rsi for storing the score of the best diagonal
	mov rsi, 64				; max mismatches possible in a 64 byte register
	; ^ this gets updated in the diagonal loops, dw about the placeholder 64

; NOTE: INSERT LIKE A CONDITIONAL? TO MASK/DEACTIVATE IF READ IS SHORT (1111)
; ---------- MAIN DIAGONAL ---------------
	; loading sequences into registers
	vmovdqu8 zmm0, [r12] ;move read seq to zmm0
	vmovdqu8 zmm1, [r13] ;move ref seq to zmm1

	;get high and low & cmp
	vpandd zmm2, zmm0, 0x0F ;read low = base1
	vpandd zmm3, zmm1, 0x0F ;ref
	vpcmpeqb k1, zmm2, zmm3 ;cmp if = -> result in k mask

	vpsrlb zmm0, zmm0, 4 ;read high = base 2
	vpsrlb zmm1, zmm1, 4 ;ref 
	vpcmpeqb k2, zmm0, zmm1 ;cmp if = -> result in k mask

	knotw k1, k1 
	knotw k2, k2

	;check if accpted counter == register length -> check if all same
	kandw k3, k1, k2 ; check if all is accepted
	kortestq k3, k3 ;if all accepted -> ZF = 1
	jz .exit

	;move to register <- k1,2
	;get first 1 (mismatch cuz we inverted it)
	; do *2 (or *2 +1) == index and globalcount	
	;compare index position (whoever smallest/if same always pick k1)
	
	;borrow stack 
	sub rsp, 16

	kmovq [rsp], k1
	kmovq [rsp + 8], k2

	mov rax, [rsp]
	tzcnt rcx, rax
	shl rcx, 1
	
	mov rax, [rsp + 8]
	tzcnt rbx, rax
	lea rbx, [rbx*2+1]
	mov rax, rbx

	cmp rax, rcx
	je .pick1
	jl .pick2
	mov qword [global_count], rcx

	.pick1:
		mov qword [global_count], rcx
	
	.pick2:
		mov qword[global_count], rax

	add rsp, 16
; ---------- LEFT and RIGHT DIAGONAL ---------------
; VERY INCOMPLETE
	; loop from edit distance 1 to edit distance threshold
	xor rdi, rdi		; the edit distance counter
	cmp r14, 0			; check if edit distance threshold is 0
	je .diagonals_done	; if 0, skip diagonals

.diagonal_loop:
	inc rdi			; increment edit distance

; ----------- DELETION / RIGHT DIAGONAL ---------------
	vmovdqu8 zmm1, [r13 + r9]	; move ref seq to zmm1 with offset
	mov rax, r12 				; move read seq pointer to rax
	; the only difference between the the left and right diagonal since ReadSeq - e
	sub rax, rdi				; offset read seq pointer by edit distance
	vmovdqu8 zmm0, [rax + r9]	; move read seq to zmm0

	; 4-bit base logic
	vpandd zmm2, zmm0, 0x0F		; read low
	vpandd zmm3, zmm1, 0x0F		; ref low
	vpcmpeqb k1, zmm2, zmm3		; k1 = low bits comparison

	vpsrlb zmm0, zmm0, 4
	vpsrlb zmm1, zmm1, 4

	vpandd zmm4, zmm0, 0x0F		; read high
	vpandd zmm5, zmm1, 0x0F		; ref high
	vpcmpeqb k2, zmm4, zmm5		; k2 = high bits comparison

	; count mismatches for this diagonal
	kandw k3, k1, k2			; k3 = combined comparison
	knotw k3, k3				; invert k3 to get mismatches
	kpopcntq rax, k3			; count mismatches in k3
	cmp rax, rsi				; compare with current mismatch count
	cmovl rsi, rax				; update best mismatch count
	; ^^^^ this may be wrong, but it finds the best alignment for this read sequence by keeping the lowest mismatch count
	; so rsi starts at 64, and after checking each diagonal, we will get the mismatches in rax
	; this will only update rsi only if the current diagonal has less mismatches than the previous best
	; so after checking all diagonals, rsi will have the lowest mismatch count found

; ----------- INSERTION / LEFT DIAGONAL ---------------
	vmovdqu8 zmm1, [r13 + r9]	; move ref seq to zmm1 with offset
	mov rax, r12 				; move read seq pointer to rax
	; the only difference between the the left and right diagonal since ReadSeq + e
	add rax, rdi				; offset read seq pointer by edit distance
	vmovdqu8 zmm0, [rax + r9]	; move read seq to zmm0

	; 4-bit base logic
	vpandd zmm2, zmm0, 0x0F		; read low
	vpandd zmm3, zmm1, 0x0F		; ref low
	vpcmpeqb k1, zmm2, zmm3		; k1 = low bits comparison

	vpsrlb zmm0, zmm0, 4
	vpsrlb zmm1, zmm1, 4

	vpandd zmm4, zmm0, 0x0F		; read high
	vpandd zmm5, zmm1, 0x0F		; ref high
	vpcmpeqb k2, zmm4, zmm5		; k2 = high bits comparison

	; count mismatches for this diagonal
	kandw k3, k1, k2			; k3 = combined comparison
	knotw k3, k3				; invert k3 to get mismatches
	kpopcntq rax, k3			; count mismatches in k3
	cmp rax, r10				; compare with current mismatch count
	cmovl rsi, rax

	; check if we reached the edit distance threshold
	cmp rdi, r14
	jne .diagonal_loop			; loop again

.diagonals_done:
	; after checking all diagonals, rsi has the lowest mismatch count found
	; move the best mismatch count to r10 for final checking
	mov r10, rsi				; update mismatch count with best found

	;mismatch

	;inc globalcounter

	;wat if we count the total then inc to reduce the branching

	;use mask to check if 0 -> exit: update the checkpoint 

	;count 1s in k masks -> inc matches?

	


	; mask -> later can be used to know how many accepts before checkpoint etc
	; count the mask -> for how many accepts for the given

	





	; updating pointers and counters
	inc qword [processed_counter]		; how many sequences has been processed
	add r9, 64							; move onto the next byte
	jmp .mainloop

.exit:
	;quick exit checker
	;check if counter == number of bytes in zmm reg


.handle_tail:
	; this is for handling the remaining unused bits in the 512 bit registers
	mov rcx, [read_bytes] ;read_bytes = remaining bytes for tail to handle
	sub rcx, r9
	test rcx, rcx
	jz .check_mismatches

	; FINISH THIS TAIL HANDLING
	lea rsi, [r12 + r9]
	lea rdi, [r13 + r9]

	;loop indexing (0 .. remaining-1)
	xor rbx, rbx

.tail_loop:
	cmp rbx, rcx
	jae .tail_done

   	mov al, byte [rsi + rbx]   ; read byte
   	mov dl, byte [rdi + rbx]   ; ref byte

	; compare low nibble: (al & 0x0F) vs (dl & 0x0F)
	movzx rax, al
	and rax, 0x0F
	movzx rdx, dl
	and rdx, 0x0F
	cmp rax, rdx
	je .no_inc_low
	inc r10                    ; increment mismatch counter

	.no_inc_low:

	; compare high nibble: (al >> 4) vs (dl >> 4)
	movzx rax, al
	shr rax, 4
	movzx rdx, dl
	shr rdx, 4
	cmp rax, rdx
	je .no_inc_high
	inc r10

	.no_inc_high:

	inc rbx
	jmp .tail_loop

	.tail_done:
   	; finished tail; fall through to mismatch check
	jmp .check_mismatches ;idt this is needed but worried about all the jumping

; ============================================================
; =============  Masked Version for Tail handling (prototype) =======
; ============================================================
; 
;hopefully this is correct
;
; Logic:
;   1. Compute bitmask k1 = (1 << rcx) - 1 for rcx leftover bytes.
;   2. Use kmovq to load mask into k1.
;   3. Perform masked loads from ReadSeq and RefSeq.
;   4. Compare low and high nibbles in parallel.
;   5. Count mismatched nibbles using popcnt.
;
;
; ============================================================
; the define is used to isolate the lower nibble so upper bits don't interfere
;%define LOW_NIBBLE_MASK 0x0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F
;
;   mov rax, 1
;   shl rax, cl                 ; rax = 1 << rcx
;   dec rax                     ; rax = (1 << tail_len) - 1
;   kmovq k1, rax               ; load mask bits into k1
;
;   ; Load up to 63 bytes using mask
;   vmovdqu8 zmm0{k1}{z}, [rsi] ; ReadSeq tail bytes
;   vmovdqu8 zmm1{k1}{z}, [rdi] ; RefSeq tail bytes
;
;   ; --- Compare low nibbles ---
;   vpbroadcastb zmm2, [low_nibble_mask] ; 
;   vpand zmm3, zmm0, zmm2      ; isolate low nibble of ReadSeq
;   vpand zmm4, zmm1, zmm2      ; isolate low nibble of RefSeq
;   vpcmpneqb k2, zmm3, zmm4    ; mismatch mask for low nibble
;
;   ; --- Compare high nibbles ---
;   vpsrlb zmm5, zmm0, 4
;   vpsrlb zmm6, zmm1, 4
;   vpcmpneqb k3, zmm5, zmm6    ; mismatch mask for high nibble
;
;   ; Combine mismatch masks and count
;   korq k4, k2, k3
;   kortestq k4, k4             ; sets flags for mismatches
;   kmovq rax, k4               ; move mask bits to GPR
;   popcnt rax, rax             ; count number of mismatches
;   add r10, rax                ; accumulate mismatch count
;
;   jmp .check_mismatches
;
; 
; ============================================================

.check_mismatches:
	; checking if mismatches are within the edit distance threshold
	mov rax, r10		; number of mismatches
	cmp rax, r14		; compare with edit threshold
	jle .accepted		; if less or equal, accepted
	jg .rejected		; if greater, rejected

.accepted:
	inc qword [accepted]
	mov eax, 1			; return 1
	jmp .cleanup

.rejected:
	inc qword [rejected]
	xor eax, eax		; return 0
	jmp .cleanup

.cleanup:
	; this just for cleanup before returning
	add rsp, 32			; restore shadow space
	pop rbx				; restore registers
	pop r15
	pop r14
	pop r13
	pop r12
	pop rdx	
	pop rsi
	pop rdi
	move rsp, rbp
	pop rbp
	ret

main:
	; this is mainly just for testing, this can be removed after everything has been verified


	xor eax, eax
	ret
