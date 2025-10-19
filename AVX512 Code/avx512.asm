%include "io.inc"

section .text
default rel
bits 64

section .data
 processed_counter dq 0		; this just for counting how many sequences have been processed
 accepted dq 0				; for counting how many sequences have been accepted
 rejected dq 0				; for counting how many sequences have been rejected
 mismatches dq 0			; for counting how many mismatches have been found
 matches dq 0				; for counting how many matches have been found
 read_bytes dq 0			; for counting how many bytes have been read (for the loop)

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

	sub rsp, 32			; shadow space -- remove this cuz we r callee

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
	vpcmpeqb k2, zmm2, zmm3 ;cmp if = -> result in k mask

	;high bit k masks -> prolly inc the index too for checkpoint
	kortestq k1, k1
	;jz .exit

	;low bit k masks 
	kortestq k2, k2
	;jz .exit

	;check if accpted counter == register length
	kandw k3, k1, k2 ; check if all is accepted
	knotw k3, k3 ;invert so if all accept = all will be 0
	kortestq k3, k3 ;if all accepted -> ZF = 1
	;TODO: add globalcounter = number of 1s here
	jz .exit

	


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