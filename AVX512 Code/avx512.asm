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
; int SneakySnake(int ReadLength, char* RefSeq, char* ReadSeq, int EditThreshold, int IterationNo)
; parameters and their corresponding registers (I AM NOT ENTIRELY SURE WITH THIS):
; int ReadLength =		rcx
; char* ReadSeq =		rdx
; char* RefSeq =		r8
; int EditThreshold =	r9
; int IterationNo =		[rsp + 8] 
; return value =		r/eax

Sneakynake:
	push rbp
	mov rbp, rsp

	push rdi			; save parameters
	push rsi			; dont know if we need these for the project, just in case lang
	push rdx
	push r12
	push r13
	push rbx

	sub rsp, 32			; shadow space

	; saving arguments into registers that we wont overwrite
	mov r9, rcx			; ReadLength
	mov r10, rdx		; RefSeq
	mov r11, r8			; ReadSeq
	mov r12, r9			; EditThreshold
	mov r13, [rsp + 8]	; IterationNo

	; r9 = ReadLength
	; r10 = RefSeq
	; r11 = ReadSeq
	; r12 = EditThreshold
	; r13 = IterationNo

	; counter for the amount of reads processed
	inc qword [processed_counter]		; for counting how many sequences have been processed

	; computing byte length of the read
	; since 8 bits is the smallest can we can work on
	; we need to divide the read length by 2 since we're working on 4-bit nucleotides
	mov rdx, r9
	shr rdx, 1				; divides readlength by 2
	mov qword [read_bytes], rdx

	; pointers
	xor rdx, rdx				; index for the read

.mainloop:
	; main loop where we compare the read to the reference
	mov r8, qword [read_bytes]	; total number of bytes to process
	cmp rdx, r8

	; termination condition

	; create function for checking if all sequences have been processed

	; counter for the processed sequences
	inc qword [processed_counter]

	; function to check if mismatches are within the edit distance threshold

	; create function for jumping to either accepted or rejected routines

.accepted:
	inc qword [accepted]
	jmp .mainloop

.rejected:
	inc qword [rejected]
	jmp .mainloop

.cleanup:
	; this just for cleanup before returning
	add rsp, 32
	move rsp, rbp
	pop rbp
	ret

main:
	; this is mainly just for testing, this can be removed after everything has been verified


	xor eax, eax
	ret

