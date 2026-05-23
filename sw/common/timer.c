#include "dev_access.h"
#include "timer.h"

unsigned int timer_get(void) 
{
    return DEV_READ(TIMER_BASE_ADDR+0);
}
