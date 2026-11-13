#pragma once
#include <os/log.h>
void FLBenchCapture(os_log_t log, os_log_type_t type, const char *format, const char *message);
#undef os_log_with_type
#define os_log_with_type(log, type, format, message) FLBenchCapture(log, type, format, message)
