#include "task_lib.h"

#define WIDTH TASK_VIEWPORT_WIDTH
#define HEIGHT TASK_VIEWPORT_HEIGHT

#define SHARED_SCORE_BASE_VADDR (PAGE_ON_DEMAND_BASE_VADDR + 0xF00)
#define CANT_PONGS 3

typedef struct taskRecord {
	uint32_t player1Score;
	uint32_t player2Score;
} taskRecord;

void task(void) {
	screen pantalla;
	volatile taskRecord* taskRecords = (taskRecord*) SHARED_SCORE_BASE_VADDR;
	// Las instancias de Pong corresponden a task_id 1, 2 y 3 (task_id 0 es Idle)
	while (true) {
		task_draw_box(pantalla, 0, 0, WIDTH, HEIGHT, ' ', C_BG_BLACK);
		task_print(pantalla, "Score 1:", 10, 5, C_FG_WHITE);
		task_print_dec(pantalla, taskRecords[1].player1Score, 2, 20, 5, C_FG_CYAN);
		task_print_dec(pantalla, taskRecords[1].player2Score, 2, 23, 5, C_FG_MAGENTA);
		task_print(pantalla, "Score 2:", 10, 10, C_FG_WHITE);
		task_print_dec(pantalla, taskRecords[2].player1Score, 2, 20, 10, C_FG_CYAN);
		task_print_dec(pantalla, taskRecords[2].player2Score, 2, 23, 10, C_FG_MAGENTA);
		task_print(pantalla, "Score 3:", 10, 15, C_FG_WHITE);
		task_print_dec(pantalla, taskRecords[3].player1Score, 2, 20, 15, C_FG_CYAN);
		task_print_dec(pantalla, taskRecords[3].player2Score, 2, 23, 15, C_FG_MAGENTA);
		syscall_draw(pantalla);
	}
}