# The "main" component: the application's own code. FreeRTOS is an ESP-IDF
# core component and is always available, so no REQUIRES line is needed.
idf_component_register(SRCS "main.c")
