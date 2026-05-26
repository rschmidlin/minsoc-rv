// SPDX-License-Identifier: Apache-2.0
//
// Copyright 2026 Raul Schmidlin

#include "timer.h"
#include "demo_system.h"
#include "minsoc_rv_system_conf.h"

unsigned int timer_get(void) 
{
    return REG32(TIMER_BASE_ADDR+0);
}
