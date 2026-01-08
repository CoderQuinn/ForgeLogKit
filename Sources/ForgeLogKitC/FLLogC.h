//
//  FLLogC.h
//  ForgeLogKitC
//
//  Created by MagicianQuinn on 2025/12/30.
//
//  Pure C os_log wrapper (no lwIP / no tun / no platform policy)
//

#pragma once
#include <stdarg.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Compile-time configurable log buffer size
 *
 * Default: 1024
 * Override via -DFL_LOG_MAX_BUF=1024
 *
 * Must be a compile-time constant (used for stack array)
 */
#ifndef FL_LOG_MAX_BUF
#define FL_LOG_MAX_BUF 1024
#endif

typedef struct FLLogCHandle *FLLogCHandle;

typedef enum {
    FL_LOG_LEVEL_DEBUG = 0,
    FL_LOG_LEVEL_INFO  = 1,
    FL_LOG_LEVEL_WARN  = 2,
    FL_LOG_LEVEL_ERROR = 3,
    FL_LOG_LEVEL_FAULT = 4,
} FLLogLevel;

/*
 * Create a log handle
 *
 * subsystem == NULL → use default subsystem
 * category  == NULL → use "Default"
 */
FLLogCHandle FLLogCCreate(const char *subsystem, const char *category);

/*
 * Destroy handle (os_log_t does not need releasing; only free the wrapper)
 */
void FLLogCDestroy(FLLogCHandle h);

/* -------- Basic string APIs -------- */

void FLLogCInfoH (FLLogCHandle h, const char *msg);
void FLLogCDebugH(FLLogCHandle h, const char *msg);
void FLLogCWarnH (FLLogCHandle h, const char *msg);
void FLLogCErrorH(FLLogCHandle h, const char *msg);
void FLLogCFaultH(FLLogCHandle h, const char *msg);

/* -------- printf / vprintf APIs --------
 *
 * Note:
 * os_log format must be a compile-time constant string.
 * Therefore the implementation does:
 *   vsnprintf → char buf[FL_LOG_MAX_BUF]
 *   os_log("%{public}s", buf)
 */

void FLLogCLogfH(
    FLLogCHandle h,
    FLLogLevel level,
    const char *fmt,
    ...
) __attribute__((format(printf, 3, 4)));

void FLLogCVLogfH(
    FLLogCHandle h,
    FLLogLevel level,
    const char *fmt,
    va_list ap
);

#ifdef __cplusplus
}
#endif
