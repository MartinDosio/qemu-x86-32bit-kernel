; ** por compatibilidad se omiten tildes **
; ==============================================================================
; TALLER System Programming - Arquitectura y Organizacion de Computadoras - FCEN
; ==============================================================================

%include "print.mac"

global start

; COMPLETAR - Declaraciones
; Parte 1: Pasaje a modo protegido
extern GDT_DESC
extern screen_draw_layout

; Parte 2: Interrupciones
extern idt_init
extern IDT_DESC
extern pic_reset
extern pic_enable

; Parte 3: Paginacion
extern mmu_init_kernel_dir
extern mmu_init_task_dir

; Parte 4: Tareas
extern tss_init
extern tasks_init
extern sched_init

; COMPLETAR - Constantes
%define CS_RING_0_SEL (1 << 3 | 0) ; GDT_CODE_0_SEL
%define DS_RING_0_SEL (3 << 3 | 0) ; GDT_DATA_0_SEL

%define GDT_IDX_TASK_INITIAL (11 << 3 | 0)
%define GDT_IDX_TASK_IDLE    (12 << 3 | 0) 

BITS 16
;; Saltear seccion de datos
jmp start

;; -------------------------------------------------------------------------- ;;
;; Seccion de datos
;; -------------------------------------------------------------------------- ;;
start_rm_msg db     'Iniciando kernel en Modo Real'
start_rm_len equ    $ - start_rm_msg

start_pm_msg db     'Iniciando kernel en Modo Protegido'
start_pm_len equ    $ - start_pm_msg

;; -------------------------------------------------------------------------- ;;
;; Seccion de código
;; -------------------------------------------------------------------------- ;;

;; Punto de entrada del kernel
BITS 16
start:
    ; ==========================================
    ; ||  (Parte 1: Pasaje a modo protegido)  ||
    ; ==========================================

    ; COMPLETAR - Deshabilitar interrupciones
    cli

    ; Cambiar modo de video a 80 X 50
    mov ax, 3
    int 16 ; set mode 03h
    xor bx, bx
    mov ax, 0x1112
    int 16 ; load 8x8 font

    ; COMPLETAR - Imprimir mensaje de bienvenida - MODO REAL
    print_text_rm start_rm_msg, start_rm_len, 2, 0, 0

    ; COMPLETAR - Habilitar A20
    call A20_enable

    ; COMPLETAR - los defines para la GDT en defines.h y las entradas de la GDT en gdt.c
    ; COMPLETAR - Cargar la GDT
    lgdt [GDT_DESC]

    ; COMPLETAR - Setear el bit PE del registro CR0
    mov edx, cr0
    or edx, 1
    mov cr0, edx

    ; COMPLETAR - Saltar a modo protegido (far jump)
    ; (recuerden que un far jmp se especifica como jmp CS_selector:address)
    jmp CS_RING_0_SEL:modo_protegido

BITS 32
modo_protegido:
    ; COMPLETAR - A partir de aca, todo el codigo se va a ejectutar en modo protegido
    ; Establecer selectores de segmentos DS, ES, GS, FS y SS en el segmento de datos de nivel 0
    mov ax, DS_RING_0_SEL
    mov ds, ax
    mov es, ax
    mov gs, ax
    mov fs, ax
    mov ss, ax

    ; COMPLETAR - Establecer el tope y la base de la pila
    mov esp, 0x25000
    mov ebp, esp

    ; COMPLETAR - Imprimir mensaje de bienvenida - MODO PROTEGIDO
    print_text_pm start_pm_msg, start_pm_len, 2, 2, 0

    ; COMPLETAR - Inicializar pantalla
    call screen_draw_layout
    
    ; ===================================
    ; ||     (Parte 3: Paginación)     ||
    ; ===================================

    ; COMPLETAR - los defines para la MMU en defines.h
    ; COMPLETAR - las funciones en mmu.c
    ; COMPLETAR - reemplazar la implementacion de la interrupcion 88 (ver comentarios en isr.asm)
    ; COMPLETAR - La rutina de atención del page fault en isr.asm
    ; COMPLETAR - Inicializar el directorio de paginas
    call mmu_init_kernel_dir

    ; COMPLETAR - Cargar directorio de paginas (está en eax por el llamado anterior)
    mov cr3, eax

    ; COMPLETAR - Habilitar paginacion (cr0.PG = 1)
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax

    ; ========================
    ; ||  (Parte 4: Tareas) ||
    ; ========================

    ; COMPLETAR - reemplazar la implementacion de la interrupcion 88 (ver comentarios en isr.asm)
    ; COMPLETAR - las funciones en tss.c
    ; COMPLETAR - Inicializar tss
    call tss_init

    ; COMPLETAR - Inicializar el scheduler
    call sched_init

    ; COMPLETAR - Inicializar las tareas
    call tasks_init

    ; ===================================
    ; ||   (Parte 2: Interrupciones)   ||
    ; ===================================

    ; COMPLETAR - las funciones en idt.c
    ; COMPLETAR - Inicializar y cargar la IDT
    call idt_init
    lidt [IDT_DESC]

    ; COMPLETAR - Reiniciar y habilitar el controlador de interrupciones (ver pic.c)
    call pic_reset
    call pic_enable

    ; COMPLETAR - Rutinas de atención de reloj, teclado, e interrupciones 88 y 89 (en isr.asm)
    ; COMPLETAR (Parte 4: Tareas)- Cargar tarea inicial
    mov ax, GDT_IDX_TASK_INITIAL
    ltr ax

    ; COMPLETAR - Habilitar interrupciones (en etapas posteriores, evaluar si se debe comentar este código)
    ;sti
    
    ; NOTA: Pueden chequear que las interrupciones funcionen forzando a que se dispare alguna excepción (lo más sencillo es usar la instrucción `int3`)
    ;int3

    ; COMPLETAR - Probar Sys_call (para etapas posteriores, comentar este código)
    ; COMPLETAR - Probar generar una excepción (para etapas posteriores, comentar este código)
    
    ; =========================
    ; ||  (Parte 4: Tareas)  ||
    ; =========================
    
    ; COMPLETAR - Inicializar el directorio de paginas de la tarea de prueba
    ;mov eax, 0x18000
    ;push eax
    ;call mmu_init_task_dir
    ;add esp, 4

    ; COMPLETAR - Cargar directorio de paginas de la tarea
    ;mov cr3, eax
    ;mov byte [0x07000000], 1
    ;mov byte [0x07000000], 1

    ; COMPLETAR - Restaurar directorio de paginas del kernel
    ;mov eax, 0x25000
    ;mov cr3, eax

    ; COMPLETAR - Acelerar clock
    mov ax, 3000 ; Menor = Mas Rapido
    out 0x40, al
    rol ax, 8
    out 0x40, al

    ; COMPLETAR - Saltar a la primera tarea: Idle
    jmp GDT_IDX_TASK_IDLE:0

    ; Ciclar infinitamente
    mov eax, 0xFFFF
    mov ebx, 0xFFFF
    mov ecx, 0xFFFF
    mov edx, 0xFFFF
    jmp $

;; -------------------------------------------------------------------------- ;;

%include "a20.asm"