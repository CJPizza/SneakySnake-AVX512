; %include "io.inc"

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
; the main prototype:
; int SneakySnake(int ReadLength, char* RefSeq, char* ReadSeq, int EditThreshold, int KmerSize, int DebugMode, int IterationNo)
; parameters and their corresponding registers:
; int ReadLength = rcx
; char* ReadSeq = rdx
; char* RefSeq = r8
; int EditThreshold = r9
; int KmerSize = [rsp + 8] --40h?
; int DebugMode = [rsp + 16] -- 48h?
; int IterationNo = [rsp + 24] -- 50h?
; return value = eax

SneakySnake:
	push rbp
	push rbx
	mov rbp, rsp
	sub rsp, 32			; shadow space

	push rdi			; save parameters
	push rsi			; dont know if we need these for the project, just in case lang
	push rdx

.arrange_reg: ;fix the registers long/short reads
	

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