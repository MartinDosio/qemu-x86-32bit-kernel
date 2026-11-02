; ==============================================================================
; TALLER System Programming - ORGANIZACION DE COMPUTADOR II - FCEN
; ==============================================================================

global _start
extern task

BITS 32
_start:
	call task
	jmp $