#pragma once
#include <os/log.h>

// Replace only the OS submission boundary in this standalone test build.
// The actual ObjC adapter, C formatting, redactor and handle code are compiled.
void FLTestCapture(os_log_t log, os_log_type_t type, const char *format, const char *message);
#undef os_log_with_type
#define os_log_with_type(log, type, format, message) FLTestCapture(log, type, format, message)
