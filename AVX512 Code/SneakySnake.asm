%include "io.inc"

section .text
default rel
bits 64

section .data
    processed_counter dq 0
    read_bytes dq 0
    global_counter dq 0 ;note: reset this after each all loop
    counter dq 0

section .rodata
    align 64
	four_mask:  times 64 db 0x0F      ; used to mask nibbles
	f0_mask: times 64 db 0xF0
    
section .text
global SneakySnake

;int SneakySnake(int ReadLength, char* ReadSeq, char* RefSeq, int EditThreshold, int IterationNo)
;parameters and their corresponding registers:
;int ReadLength = rcx
;char* ReadSeq = rdx
;char* RefSeq = r8
;int EditThreshold = r9
;int IterationNo = [rbp + 8] 
;return value =	r/eax

SneakySnake:
    push rbp
    mov rbp, rsp

    push rdi
    push rsi
    push rdx
    push r12
    push r13
    push r14
    push r15
    push rbx

    ;move parameters to local registers
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

    ; computing byte length of the read
	; since 8 bits is the smallest can we can work on
	; we need to divide the read length by 2 since working on 4-bit nucleotides
	mov rdx, r11		
	shr rdx, 1				; divides readlength by 2
	mov qword [read_bytes], rdx

	; pointers and counters
	xor rdx, rdx				; index for the read
	xor r9, r9					; offset for bytes

    .mainloop:
		; mov qword[global_counter], 0 i think hereeeeeee
        mov rcx, [read_bytes]
        cmp r9, rcx ;compare offset with read bytes
        jae .handle_tail

        ; ADDED rsi for storing the score of the best diagonal
        mov rsi, 64				; max mismatches possible in a 64 byte register
        ; ^ this gets updated in the diagonal loops, dw about the placeholder 64

        ; load sequences into registers
        vmovdqu8 zmm0, [r12 + r9] ;read
        vmovdqu8 zmm1, [r13 + r9] ;ref
        
        ;check if current zmms are all 1111s
        vpcmpeqb k1, zmm0, [ones_mask]    ;cmp if it matches 1111s
        vpcmpeqb k2, zmm1, [ones_mask]    ;cmp if it matches 1111s
        kortestq k1, k1
        kortestq k2, k2
        jnz .skip ;if yes .skip

        ;do smthn about the 1111s in the sequences
        ;-------- MAIN DIAGONAL -------------
    
		; base2
		vpandd   zmm2, zmm0, [four_mask]   ; read low
		vpandd   zmm3, zmm1, [four_mask]   ; ref  low

		; base1
		vpandd   zmm4, zmm0, [f0_mask]     ;keep (new) low 4 bits
		vpandd   zmm5, zmm1, [f0_mask]
		vpsrld  zmm4, zmm4, 4          ; read >> 4
		vpsrld  zmm5, zmm5, 4          ; ref  >> 4
		
		vpcmpeqb k3,   zmm2, zmm3          ; k3 = base2 (end)
		vpcmpeqb k4,   zmm4, zmm5          ; k4 = base1 (start)

        knotq k3, k3
        knotq k4, k4 ;invert -> mismatch = 1

        ;check if all bases matched
        korq k5, k3, k4 
        ktestq k5, k5
        jnz .exit1
		add qword[global_counter], 128 ;not sure -> cuz like if less than a certain threshold tail handling...
		;do we always cmp if its same length then quick exit???

	.exit1:
        kmovq rbx, k3
        kmovq r10, k4

        tzcnt rbx, rbx ;get the index
        shl rbx, 1 ;2i -> index and globalcount

        tzcnt r10, r10
        lea r10, [r10*2+1] ;2i+1

        ;compare index position (whoever smallest/if same always pick k3)
        cmp rbx, r10
        cmovnb rbx, r10
        mov [global_counter], rbx
		
; ---------- LEFT and RIGHT DIAGONAL ---------------
;r14 - EditThreshold
	;mov the stuff from above to new registers here -- reuse
	xor r8, r8
	mov r8, [global_counter] ;not sure register
	
	vmovdqu8 zmm6, zmm2
	vmovdqu8 zmm7, zmm4 ;right reads

	vmovdqu8 zmm8, zmm2
	vmovdqu8 zmm9, zmm4 ;left reads

	; loop from edit distance 1 to edit distance threshold
	kxorq k3, k3
	kxorq k4, k4
	kxorq k5, k5 

	xor rbx, rbx		; the edit distance counter
	xor r10, r10
	cmp r14, 0			; check if edit distance threshold is 0
	je .diagonals_done	; if 0, skip diagonals

;.diagonal_loop: move ts
	inc rbx			; increment edit distance

; ----------- DELETION / RIGHT DIAGONAL (index - e) ---------------
	;shift them -- just keep shifting this every loop
	;same algo above with matching or not
	;unsolved: n < e -- prolly zero out masking 

	vpsrld zmm6, zmm6, 4
	vpsrld zmm7, zmm7, 4 ;shift right 
	; have problem with boundary -- fix

	vpcmpeqb k3, zmm6, zmm3 
	vpcmpeqb k4, zmm7, zmm4 ;k3&4 = cmp with shifted read and ref

	knotq k3, k3
	knotq k4, k4 ;invert -> mismatch = 1

	;check if all bases matched
	korq k5, k3, k4 
	ktestq k5, k5
	jnz .exit2
	add qword[counter], 128 ;not sure -> cuz like if less than a certain threshold tail handling...
	;do we always cmp if its same length then quick exit???

.exit2:
	kmovq rbx, k3
	kmovq r10, k4

	tzcnt rbx, rbx ;get the index
	shl rbx, 1 ;2i -> index and count

	tzcnt r10, r10
	lea r10, [r10*2+1] ;2i+1

	;compare index position (whoever smallest/if same always pick k3)
	cmp rbx, r10
	cmovnb rbx, r10
	mov [counter], rbx

	

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

.handle_tail:
	; this is for handling the remaining unused bits in the 512 bit registers
	mov rcx, [read_bytes]
	sub rcx, r9
	test rcx, rcx
	jz .check_mismatches

	; FINISH THIS TAIL HANDLING

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