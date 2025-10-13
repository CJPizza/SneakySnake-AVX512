; %include "io.inc"

section .text
default rel
bits 64

section .data
 processed_counter dq 0		; this just for counting how many sequences have been processed
 accepted dq 0				; for counting how many sequences have been accepted
 rejected dq 0				; for counting how many sequences have been rejected

global SneakySnake
; the main prototype:
; int SneakySnake(int ReadLength, char* RefSeq, char* ReadSeq, int EditThreshold, int KmerSize, int DebugMode, int IterationNo)
; parameters and their corresponding registers (I AM NOT ENTIRELY SURE WITH THIS):
; int ReadLength	= rdi
; char* RefSeq		= rsi
; char* ReadSeq		= rdx
; int EditThreshold = rcx
; int KmerSize		= r8
; int DebugMode		= r9
; int IterationNo	= [rsp + 8]		; i think this is correct cause a 7th parameter doesnt have an explicit register, so just pass it onto the stack
; return value		= eax

SneakySnake:
	push rbp
	mov rbp, rsp
	sub rsp, 32			; shadow space

	push rdi			; save parameters
	push rsi			; dont know if we need these for the project, just in case lang
	push rdx

.arrange_reg: ;fix the registers long/short reads
	vmovdqu zmm0, zmmword [rsi]	; load reference sequence into zmm0
	vmovdqu zmm1, zmmword [rdx]	; load read sequence into zmm1

	;tail handling or smthn
	
.main_diag:
	

	; main loop where we compare the read to the reference

	; create function for checking if all sequences have been processed

	; counter for the processed sequences
	inc qword [processed_counter]

	; function to check if mismatches are within the edit distance threshold

	; create function for jumping to either accepted or rejected routines

.updown_diag:
	

.accepted:
	inc qword [accepted]
	jmp .mainloop

.rejected:
	inc qword [rejected]
	jmp .mainloop

.cleanup:
	; this just for cleanup before returning
	add rsp, 32
	mov rsp, rbp
	pop rbp
	ret