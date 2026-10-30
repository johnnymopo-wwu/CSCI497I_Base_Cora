#include "xil_printf.h"
#include "xil_io.h"
#include "xparameters.h"
#include "sleep.h"

#define LED_REG_ADDR  (XPAR_AXIL_REGS_0_BASEADDR + 0x04)

int main(void)
{
    xil_printf("Blinking LED\r\n");

    while (1) {
        Xil_Out32(LED_REG_ADDR, 0x1);
        usleep(500000);
        Xil_Out32(LED_REG_ADDR, 0x0);
        usleep(500000);
    }

    return 0;
}
