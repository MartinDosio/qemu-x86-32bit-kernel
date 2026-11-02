; ** por compatibilidad se omiten tildes **
; ==============================================================================
; System Programming - ORGANIZACION DE COMPUTADOR II - FCEN
; ==============================================================================
;
; Definicion de rutinas de atencion de interrupciones

%include "print.mac"

%define CS_RING_0_SEL  (1 << 3 | 0)
%define GDT_CODE_3_SEL (2 << 3 | 3)
%define GDT_DATA_3_SEL (4 << 3 | 3)

%define TASK_CODE_VIRTUAL 0x08000000
%define TASK_STACK_BASE   0x08003000
%define KERNEL_STACK      0x00025000

; Offsets de la estructura task_t (definida en task_defines.h, tamaño 48 bytes)
%define TASK_OFFSET_SCHED_STATE 0
%define TASK_OFFSET_EAX         4
%define TASK_OFFSET_EBX         8
%define TASK_OFFSET_ECX         12
%define TASK_OFFSET_EDX         16
%define TASK_OFFSET_ESI         20
%define TASK_OFFSET_EDI         24
%define TASK_OFFSET_ESP         28
%define TASK_OFFSET_EBP         32
%define TASK_OFFSET_EIP         36
%define TASK_OFFSET_EFLAGS      40
%define TASK_OFFSET_CR3         44
%define TASK_SIZE               48

%define SHARED_TICK_COUNT 0x1D000

BITS 32

; sched_task_offset:     dd 0xFFFFFFFF
; sched_task_selector:   dw 0xFFFF

;; Procesar Tecla (Parte 2: Interrupciones)
extern process_scancode

;; PIC
extern pic_finish1

;; Sched
extern sched_next_task
extern kernel_exception
extern page_fault_handler

;; Tasks
extern tasks_tick
extern tasks_screen_update
extern tasks_syscall_draw
extern tasks_input_process
extern tasks
extern current_task

;; Definición de MACROS
;; -------------------------------------------------------------------------- ;;

%macro ISRc 1
    push DWORD %1
    ; Stack State:
    ; [ INTERRUPT #] esp
    ; [ ERROR CODE ] esp + 0x04
    ; [ EIP        ] esp + 0x08
    ; [ CS         ] esp + 0x0c
    ; [ EFLAGS     ] esp + 0x10
    ; [ ESP        ] esp + 0x14 (if DPL(cs) == 3)
    ; [ SS         ] esp + 0x18 (if DPL(cs) == 3)

    ; GREGS
    pushad
    ; Check for privilege change before anything else.
    mov edx, [esp + (8*4 + 3*4)]

    ; SREGS
    xor eax, eax
    mov ax, ss
    push eax
    mov ax, gs
    push eax
    mov ax, fs
    push eax
    mov ax, es
    push eax
    mov ax, ds
    push eax
    mov ax, cs
    push eax

    ; CREGS
    mov eax, cr4
    push eax
    mov eax, cr3
    push eax
    mov eax, cr2
    push eax
    mov eax, cr0
    push eax

    cmp edx, CS_RING_0_SEL
    je .ring0_exception

    ; COMPLETAR (opcional) (Parte 4: Tareas):
    ;   Si caemos acá es porque una tarea causó una excepción
    ;   En lugar de frenar el sistema podríamos matar la tarea (o reiniciarla)
    ;   ¿Cómo harían eso?
    call kernel_exception
    add esp, 10*4
    popad

    xchg bx, bx
    jmp $

.ring0_exception:
    call kernel_exception
    add esp, 10*4
    popad

    xchg bx, bx
    jmp $

%endmacro

; ISR that pushes an exception code.
%macro ISRE 1
global _isr%1

_isr%1:
  ISRc %1
%endmacro

; ISR That doesn't push an exception code.
%macro ISRNE 1
global _isr%1

_isr%1:
  push DWORD 0x0
  ISRc %1
%endmacro

;; Rutina de atención de las EXCEPCIONES
;; -------------------------------------------------------------------------- ;;
ISRNE 0
ISRNE 1
ISRNE 2
ISRNE 3
ISRNE 4
ISRNE 5
ISRNE 6
ISRNE 7
ISRE 8
ISRNE 9
ISRE 10
ISRE 11
ISRE 12
ISRE 13
;ISRE 14 ; comentar esta línea en la parte 3 (paginación)
ISRNE 15
ISRNE 16
ISRE 17
ISRNE 18
ISRNE 19
ISRNE 20

;; Rutina de atención de Page Fault ISRE 14 ; Descomentar esta rutina en la parte 3 (paginación)
;; -------------------------------------------------------------------------- ;;
global _isr14
_isr14:
    pushad
    mov eax, cr2
    push eax    ; cr2 como parametro (contiene la direccion lineal que provocó el fallo)
    call page_fault_handler
	add esp, 4  ; acomodo la pila

    ; si pudo atender la excepcion, continúo
    cmp al, 1
    je .fin

    ; si no, loopeo infinitamente
    call kernel_exception
    jmp $

    .fin:
    popad
	add esp, 4 ; error code
	iret

;; Rutina de atención del RELOJ
;; -------------------------------------------------------------------------- ;;
global _isr32
; COMPLETAR (Parte 2: Interrupciones): La rutina se encuentra escrita parcialmente. Completar la rutina
_isr32:
    pushad
    call save_current_task_context

    ; 1. Le decimos al PIC que vamos a atender la interrupción
    call pic_finish1
    
    ; 2. Imprimimos el reloj que gira en pantalla
    call next_clock
    
    ; 3. (Parte 4: Tareas) Realizamos la planificación para seleccionar la próxima tarea
    call sched_next_task

    ; 4. Actualizamos las estructuras compartidas ante el tick del reloj
    call tasks_tick
    
    ; 5. Actualizamos la "interfaz" del sistema en pantalla
    call tasks_screen_update

    ; 6. (Parte 4: Tareas - Punto 12) Realizamos el cambio de contexto a la tarea actual
    ; Nota: switch_to_usermode no retorna aquí, sino que ejecuta su propio iret hacia Ring 3.
    call switch_to_usermode

;; Rutina de atención del TECLADO
;; -------------------------------------------------------------------------- ;;
global _isr33
; COMPLETAR: Implementar la rutina
_isr33:
    pushad
    ; 1. Le decimos al PIC que vamos a atender la interrupción
    call pic_finish1
    
    ; 2. Leemos la tecla desde el teclado y la procesamos con la funcion process_scancode (Durante Parte 2: Interrupciones) o tasks_input_process (Durante Parte 4: Tareas)
    in al, 0x60
    push eax
    call tasks_input_process
    add esp, 4
    
    popad
    iret


;; Rutinas de atención de las SYSCALLS
;; -------------------------------------------------------------------------- ;;

global _isr88
; COMPLETAR: Implementar la rutina
; Para la seccion de interrupciones: que modifique el valor de eax por 0x58
; Para la seccion de tareas: que llame a la funcion task_syscall_draw
_isr88:
    pushad
    push eax
    call tasks_syscall_draw
    add esp, 4
    popad
    iret

; COMPLETAR: Implementar la rutina
; La rutina debe modificar el valor de eax por 0x62
global _isr98
_isr98:
    mov eax, 0x62
    iret

; PushAD Order
%define offset_EAX 28
%define offset_ECX 24
%define offset_EDX 20
%define offset_EBX 16
%define offset_ESP 12
%define offset_EBP 8
%define offset_ESI 4
%define offset_EDI 0

;; Rutina para guardar el contexto de la tarea actual (Punto 13)
;; -------------------------------------------------------------------------- ;;
global save_current_task_context
save_current_task_context:
    ; Puntero al inicio del frame de pushad en la pila de Ring 0:
    ; [esp] contiene la dirección de retorno del call a save_current_task_context.
    ; [esp + 4] apunta al frame de pushad ejecutado en _isr32 (donde está EDI).
    lea esi, [esp + 4]

    ; Obtenemos la dirección del struct task_t correspondiente a la tarea actual:
    ; &tasks[current_task] = tasks + current_task * TASK_SIZE
    mov eax, [current_task]
    imul eax, TASK_SIZE
    lea edi, [tasks + eax]

    ; 1. Guardar los registros de propósito general desde el stack frame de pushad
    mov eax, [esi + offset_EAX]
    mov [edi + TASK_OFFSET_EAX], eax

    mov eax, [esi + offset_EBX]
    mov [edi + TASK_OFFSET_EBX], eax

    mov eax, [esi + offset_ECX]
    mov [edi + TASK_OFFSET_ECX], eax

    mov eax, [esi + offset_EDX]
    mov [edi + TASK_OFFSET_EDX], eax

    mov eax, [esi + offset_ESI]
    mov [edi + TASK_OFFSET_ESI], eax

    mov eax, [esi + offset_EDI]
    mov [edi + TASK_OFFSET_EDI], eax

    mov eax, [esi + offset_EBP]
    mov [edi + TASK_OFFSET_EBP], eax

    ; 2. Guardar los registros del frame de interrupción generado por la CPU
    ; al ocurrir la transición de privilegios (Ring 3 -> Ring 0):
    ; [esi + 32] -> EIP
    ; [esi + 36] -> CS
    ; [esi + 40] -> EFLAGS
    ; [esi + 44] -> ESP de usuario (Ring 3)
    ; [esi + 48] -> SS de usuario (Ring 3)
    mov eax, [esi + 44] ; ESP de la tarea en modo usuario
    mov [edi + TASK_OFFSET_ESP], eax

    mov eax, [esi + 32] ; EIP de la tarea
    mov [edi + TASK_OFFSET_EIP], eax

    mov eax, [esi + 40] ; EFLAGS de la tarea
    mov [edi + TASK_OFFSET_EFLAGS], eax

    ; 3. Guardar el registro de control CR3 (directorio de páginas de la tarea)
    mov eax, cr3
    mov [edi + TASK_OFFSET_CR3], eax

    ret

;; Rutina para cambiar a modo usuario y ejecutar la tarea actual (Puntos 8 y 10)
;; -------------------------------------------------------------------------- ;;
global switch_to_usermode
switch_to_usermode:
    ; 1. Obtener la entrada correspondiente en el array de tareas (tasks)
    mov ebx, [current_task]
    imul ebx, TASK_SIZE
    add ebx, tasks

    ; 2. Cargar el esquema de paginación de la tarea (CR3)
    mov eax, [ebx + TASK_OFFSET_CR3]
    mov cr3, eax

    ; 3. Establecer los selectores de segmentos de datos para nivel de usuario (RPL = 3)
    mov ax, GDT_DATA_3_SEL
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    ; 4. Limpiar la pila de kernel situando ESP en KERNEL_STACK (0x25000)
    ;    (descarta la dirección de retorno del call que invocó a switch_to_usermode)
    mov esp, KERNEL_STACK

    ; 5. Armar el stack frame en la pila del kernel para retornar a Ring 3 mediante iret:
    ;    [esp + 16] -> SS (selector de segmento de datos de usuario con RPL = 3)
    ;    [esp + 12] -> ESP (puntero a la pila de usuario, desde task_t)
    ;    [esp + 8]  -> EFLAGS (flags de la tarea, desde task_t)
    ;    [esp + 4]  -> CS (selector de segmento de código de usuario con RPL = 3)
    ;    [esp + 0]  -> EIP (dirección virtual de inicio de la tarea, desde task_t)
    push GDT_DATA_3_SEL
    push DWORD [ebx + TASK_OFFSET_ESP]
    push DWORD [ebx + TASK_OFFSET_EFLAGS]
    push GDT_CODE_3_SEL
    push DWORD [ebx + TASK_OFFSET_EIP]

    ; 6. Restaurar los registros de propósito general desde la estructura task_t
    mov eax, [ebx + TASK_OFFSET_EAX]
    mov ecx, [ebx + TASK_OFFSET_ECX]
    mov edx, [ebx + TASK_OFFSET_EDX]
    mov esi, [ebx + TASK_OFFSET_ESI]
    mov edi, [ebx + TASK_OFFSET_EDI]
    mov ebp, [ebx + TASK_OFFSET_EBP]
    mov ebx, [ebx + TASK_OFFSET_EBX]    ; ebx se restaura último pues se usa como base

    ; 7. Cambiar a modo usuario e iniciar la ejecución de la tarea
    iret


;; Funciones Auxiliares
;; -------------------------------------------------------------------------- ;;
isrNumber:           dd 0x00000000
isrClock:            db '|/-\'
clock_ticks:         dd 0x00000000
next_clock:
    pushad
    inc DWORD [clock_ticks]
    cmp DWORD [clock_ticks], 250 ; Con PIT a ~1000 Hz: cada 250 ticks (250 ms) avanza 1 caracter (1 giro completo por segundo)
    jl .fin
    mov DWORD [clock_ticks], 0

    inc DWORD [isrNumber]
    mov ebx, [isrNumber]
    cmp ebx, 0x4
    jl .ok
        mov DWORD [isrNumber], 0x0
        mov ebx, 0
    .ok:
        add ebx, isrClock
        print_text_pm ebx, 1, 0x0f, 49, 79
    .fin:
        popad
    ret