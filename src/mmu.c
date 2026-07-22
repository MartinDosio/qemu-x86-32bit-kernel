/* ** por compatibilidad se omiten tildes **
================================================================================
 TRABAJO PRACTICO 3 - System Programming - ORGANIZACION DE COMPUTADOR II - FCEN
================================================================================

  Definicion de funciones del manejador de memoria
*/

#include "mmu.h"
#include "i386.h"
#include "kassert.h"

static pd_entry_t* kpd = (pd_entry_t*)KERNEL_PAGE_DIR;
static pt_entry_t* kpt = (pt_entry_t*)KERNEL_PAGE_TABLE_0;

static const uint32_t identity_mapping_end = 0x003FFFFF;
static const uint32_t user_memory_pool_end = 0x02FFFFFF;

static paddr_t next_free_kernel_page = 0x100000;
static paddr_t next_free_user_page = 0x400000;

/**
 * kmemset asigna el valor c a un rango de memoria interpretado como un rango de bytes de largo n que comienza en s
 * @param s es el puntero al comienzo del rango de memoria
 * @param c es el valor a asignar en cada byte de s[0..n-1]
 * @param n es el tamaño en bytes a asignar
 * @return puntero al rango modificado (alias de s)
*/
static inline void* kmemset(void* s, int c, size_t n) {
    uint8_t* dst = (uint8_t*)s;

    for (size_t i = 0; i < n; i++) {
        dst[i] = c;
    }

    return dst;
}

/**
 * zero_page limpia el contenido de una página que comienza en addr
 * @param addr es la dirección del comienzo de la página a limpiar
*/
static inline void zero_page(paddr_t addr) {
    kmemset((void*)addr, 0x00, PAGE_SIZE);
}

void mmu_init(void) {}

/**
 * mmu_next_free_kernel_page devuelve la dirección física de la próxima página de kernel disponible. 
 * Las páginas se obtienen en forma incremental, siendo la primera: next_free_kernel_page
 * @return devuelve la dirección de memoria de comienzo de la próxima página libre de kernel
 */
paddr_t mmu_next_free_kernel_page(void) {
    paddr_t res = next_free_kernel_page;
    next_free_kernel_page += PAGE_SIZE;
    return res;
}

/**
 * mmu_next_free_user_page devuelve la dirección de la próxima página de usuario disponible
 * @return devuelve la dirección de memoria de comienzo de la próxima página libre de usuario
 */
paddr_t mmu_next_free_user_page(void) {
    paddr_t res = next_free_user_page;
    next_free_user_page += PAGE_SIZE;
    return res;
}

/**
 * mmu_init_kernel_dir inicializa las estructuras de paginación vinculadas al kernel y realiza el identity mapping
 * @return devuelve la dirección de memoria de la página donde se encuentra el directorio de páginas usado por el kernel
 */
paddr_t mmu_init_kernel_dir(void) {
    // Limpio el page directory y la page table
    zero_page((paddr_t)kpd);
    zero_page((paddr_t)kpt);

    // Primera entrada del page directory
    kpd[0].pt = ((uint32_t)kpt) >> 12;
    kpd[0].attrs = MMU_P | MMU_W;

    // Identity Mapping para los primeros 4MB
    for (size_t i = 0; i < 1024; i++) {
        kpt[i].page = i;
        kpt[i].attrs = MMU_P | MMU_W;
    }
    
    // Devuelvo la dirección física del Page Directory
    return (paddr_t)kpd;
}

/**
 * mmu_map_page agrega las entradas necesarias a las estructuras de paginación de modo de que la dirección virtual virt se traduzca en la dirección física phy con los atributos definidos en attrs
 * @param cr3 el contenido que se ha de cargar en un registro CR3 al realizar la traducción
 * @param virt la dirección virtual que se ha de traducir en phy
 * @param phy la dirección física que debe ser accedida (dirección de destino)
 * @param attrs los atributos a asignar en la entrada de la tabla de páginas
 */
void mmu_map_page(uint32_t cr3, vaddr_t virt, paddr_t phy, uint32_t attrs) {
    // Obtengo indices y el puntero al directorio
    paddr_t pd_index = VIRT_PAGE_DIR(virt);
    paddr_t pt_index = VIRT_PAGE_TABLE(virt);
    pd_entry_t* pd = (pd_entry_t*)CR3_TO_PAGE_DIR(cr3);

    // Si la page table no existe la creo
    if (!(pd[pd_index].attrs & MMU_P)) {
        paddr_t nueva_pt_paddr = mmu_next_free_kernel_page();
        zero_page(nueva_pt_paddr);

        pd[pd_index].pt = nueva_pt_paddr >> 12;
        pd[pd_index].attrs = attrs | MMU_P;
    }
    
    // Obtengo el puntero a la tabla de paginas y la mapeo
    pt_entry_t* pt = (pt_entry_t*)MMU_ENTRY_PADDR(pd[pd_index].pt);
    pt[pt_index].page = phy >> 12;
    pt[pt_index].attrs = attrs | MMU_P;

    // Limpio cache de traducciones
    tlbflush();
}

/**
 * mmu_unmap_page elimina la entrada vinculada a la dirección virt en la tabla de páginas correspondiente
 * @param virt la dirección virtual que se ha de desvincular
 * @return la dirección física de la página desvinculada
 */
paddr_t mmu_unmap_page(uint32_t cr3, vaddr_t virt) {
    // Obtengo indices y el puntero al directorio
    paddr_t pd_index = VIRT_PAGE_DIR(virt);
    paddr_t pt_index = VIRT_PAGE_TABLE(virt);
    pd_entry_t* pd = (pd_entry_t*)CR3_TO_PAGE_DIR(cr3);
    pt_entry_t* pt = (pt_entry_t*)MMU_ENTRY_PADDR(pd[pd_index].pt);

    // Guardo la direccion fisica de destino antes de borrarla
    paddr_t phy = (paddr_t)MMU_ENTRY_PADDR(pt[pt_index].page);
    
    // Desmapeo la pagina
    pt[pt_index].page = 0;
    pt[pt_index].attrs = 0;

    // Limpio cache de traducciones y retorno
    tlbflush();
    return phy;
}

#define DST_VIRT_PAGE 0xA00000
#define SRC_VIRT_PAGE 0xB00000

/**
 * copy_page copia el contenido de la página física localizada en la dirección src_addr a la página física ubicada en dst_addr. Mapea ambas páginas a las direcciones SRC_VIRT_PAGE y DST_VIRT_PAGE, respectivamente, realiza la copia y luego desmapea las páginas. Usar la función rcr3 definida en i386.h para obtener el cr3 actual
 * @param dst_addr la dirección a cuya página queremos copiar el contenido
 * @param src_addr la dirección de la página cuyo contenido queremos copiar
 */
void copy_page(paddr_t dst_addr, paddr_t src_addr) {
    // Obtengo cr3
    uint32_t cr3 = rcr3();

    // Mapeo las paginas
    mmu_map_page(cr3, SRC_VIRT_PAGE, src_addr, MMU_W);
    mmu_map_page(cr3, DST_VIRT_PAGE, dst_addr, MMU_W);

    // Copio la pagina entera de a 4 bytes (por eficiencia)
    uint32_t* src = (uint32_t*)SRC_VIRT_PAGE;
    uint32_t* dst = (uint32_t*)DST_VIRT_PAGE;

    for (size_t i = 0; i < 1024; i++) {
        dst[i] = src[i];
    }

    // Desmapeo las paginas
    mmu_unmap_page(cr3, SRC_VIRT_PAGE);
    mmu_unmap_page(cr3, DST_VIRT_PAGE);
}

/**
 * mmu_init_task_dir inicializa las estructuras de paginación vinculadas a una tarea cuyo código se encuentra en la dirección phy_start
 * @param phy_start es la dirección donde comienzan las dos páginas de código de la tarea asociada a esta llamada
 * @return el contenido que se ha de cargar en un registro CR3 para la tarea asociada a esta llamada
 */
paddr_t mmu_init_task_dir(paddr_t phy_start) {
    // Asigno una nueva pagina fisica para el directorio de paginas de la tarea
    paddr_t task_pd_paddr = mmu_next_free_kernel_page();
    zero_page(task_pd_paddr);

    // Identity Mapping de los primeros 4MB del kernel
    for (size_t i = 0; i < identity_mapping_end; i += PAGE_SIZE) {
        mmu_map_page(task_pd_paddr, i, i, MMU_P | MMU_W);
    }

    // Mapeo las paginas de codigo de la tarea
    for (size_t i = 0; i < TASK_CODE_PAGES; i++) {
        mmu_map_page(task_pd_paddr, TASK_CODE_VIRTUAL + (i*PAGE_SIZE), phy_start + (i*PAGE_SIZE), MMU_P | MMU_W | MMU_U);
    }

    // Mapeo la pagina de pila
    mmu_map_page(task_pd_paddr, TASK_STACK_BASE - PAGE_SIZE, mmu_next_free_user_page(), MMU_P | MMU_U | MMU_W);

    // Mapeo la pagina compartida
    mmu_map_page(task_pd_paddr, TASK_SHARED_PAGE, SHARED, MMU_P | MMU_U | MMU_W);
    
    // Retorno la direccion del nuevo directorio de paginas
    return task_pd_paddr;
}

// COMPLETAR: devuelve true si se atendió el page fault y puede continuar la ejecución 
// y false si no se pudo atender
bool page_fault_handler(vaddr_t virt) {
    print("Atendiendo page fault...", 0, 0, C_FG_WHITE | C_BG_BLACK);
    // Chequeemos si el acceso fue dentro del area on-demand
    // En caso de que si, mapear la pagina
    if ((virt >= ON_DEMAND_MEM_START_VIRTUAL) & (virt <= ON_DEMAND_MEM_END_VIRTUAL)) {
        uint32_t cr3 = rcr3();
        mmu_map_page(cr3, virt, ON_DEMAND_MEM_START_PHYSICAL, MMU_U | MMU_W | MMU_P);
        return true;
    }

    return false;
}