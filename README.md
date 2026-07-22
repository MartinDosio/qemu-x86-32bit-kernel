# Kernel x86 de 32 bits con QEMU

Un kernel mínimo de 32 bits para Intel x86, desarrollado desde cero como parte del **Taller de Programación de Sistemas** en la **Facultad de Ciencias Exactas y Naturales de la UBA** (Arquitectura y Organización de Computadores).

## Descripción General

El kernel arranca desde una imagen de disquete (*floppy disk*) utilizando QEMU. Una vez que la BIOS le cede la ejecución, el procesador pasa de Modo Real a Modo Protegido de 32 bits y construye el entorno de ejecución completo desde cero: sin un sistema operativo por debajo ni biblioteca estándar.

Configura la segmentación (GDT), el manejo de interrupciones (IDT) y la memoria virtual mediante un esquema de paginación de dos niveles con espacios de direcciones aislados por tarea. El cambio de tareas se realiza asistido por hardware a través de descriptores TSS, mientras que un planificador (*scheduler*) *round-robin* apropiativo basado en el temporizador PIT mantiene ejecutándose cuatro tareas concurrentes en espacio de usuario (Ring 3).

Las tareas son juegos interactivos que se renderizan en simultáneo en distintos cuadrantes de la pantalla: **Pong** (dos jugadores, controlado por teclado), **Snake**, el **Juego de la Vida de Conway** y un juego de mecanografía (*typing game*). Cada tarea se comunica con el kernel a través de una página de memoria compartida (estado del teclado, contador de *ticks*, ID de la tarea) y mediante la interrupción `syscall_draw` para renderizar su cuadrante (*viewport*).

## Características

- Transición a Modo Protegido con GDT (segmentos de código y datos para Ring 0 y Ring 3)
- IDT con rutinas de atención (*handlers*) para excepciones de la CPU (0–20), IRQs de hardware (temporizador, teclado) y llamadas al sistema (*syscalls*) por software (`int 88` / `int 98`)
- Paginación de dos niveles con directorio de páginas (*page directory*) por tarea, mapeo identidad (*identity mapping*) para el kernel y mapeo a demanda para el rango de memoria `0x07000000–0x07000FFF`
- Planificador *round-robin* con estados de tarea `RUNNABLE`, `PAUSED` y `FREE`, además de una tarea nula (*idle task*) de respaldo
- Página de memoria compartida mapeada en el espacio de direcciones virtuales de cada tarea para la comunicación entre el kernel y las tareas

## Cómo ejecutar

### Requisitos

- `gcc` con soporte para `-m32`
- `nasm`
- `qemu-system-i386`
- `gdb`
- `mtools`
- `bzip2`

### Ejecución

```bash
cd src
make gdb    # compila el kernel e inicia QEMU + gdb
continue    # inicia la maquina virtual
```

## Referencias

- [Intel SDM Vol. 1 – Basic Architecture](https://software.intel.com/content/dam/develop/external/us/en/documents-tps/253665-sdm-vol-1.pdf)

- [Intel SDM Vol. 2 – Instruction Set Reference](https://software.intel.com/content/dam/develop/external/us/en/documents-tps/325383-sdm-vol-2abcd.pdf)

- [Intel SDM Vol. 3 – System Programming Guide](https://software.intel.com/content/dam/develop/external/us/en/documents-tps/325384-sdm-vol-3abcd.pdf)

> La documentación detallada de cada etapa (Modo Protegido, Interrupciones, Paginación, Tareas) se encuentra disponible en los archivos de texto respectivamente numerados