/*
 * main.c - minimal FreeRTOS test for the ESP32.
 *
 * ESP-IDF's startup code has already started the FreeRTOS scheduler and
 * calls app_main() from a task named "main". We create one more task that
 * prints a line every second, which proves that task creation, the
 * scheduler and the tick timer all work.
 */
#include <stdio.h>              /* printf: ESP-IDF routes it to UART0 */
#include "freertos/FreeRTOS.h"  /* must come before any other FreeRTOS header */
#include "freertos/task.h"      /* xTaskCreate, vTaskDelay, xTaskGetTickCount */

/* Body of our task. A FreeRTOS task is a function that never returns. */
static void hello_task(void *arg)
{
    for (;;) {
        /* Ticks since the scheduler started (CONFIG_FREERTOS_HZ per sec). */
        printf("Hello from a FreeRTOS task! tick=%lu\n",
               (unsigned long)xTaskGetTickCount());

        /* Block this task for 1000 ms; the scheduler runs others meanwhile. */
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}

void app_main(void)
{
    /* Create the task:
     *   hello_task  function to run
     *   "hello"     name (for debugging)
     *   2048        stack size; in ESP-IDF this is in BYTES, not words
     *   NULL        argument passed to hello_task
     *   5           priority (higher number = higher priority)
     *   NULL        we don't need the task handle back */
    xTaskCreate(hello_task, "hello", 2048, NULL, 5, NULL);

    /* Returning is fine: ESP-IDF deletes the "main" task, and hello_task
     * keeps running. */
}
