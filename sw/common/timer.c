// SPDX-License-Identifier: Apache-2.0
//
// Copyright 2026 Raul Schmidlin

#include "dev_access.h"
#include "demo_system_regs.h"
#include "timer.h"

unsigned int timer_get(void) 
{
    return DEV_READ(TIMER_BASE_ADDR+0);
}
