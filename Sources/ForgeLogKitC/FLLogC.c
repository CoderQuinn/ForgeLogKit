//
//  FLLogC.c
//  ForgeLogKitC
//
//  Created by MagicianQuinn on 2025/12/30.
//

#include "FLLogC.h"
#include <os/log.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* ================= internal ================= */

struct FLLogCHandle {
    os_log_t log;
    const char *category;   /* owned copy */
};

static const char *FLDefaultSubsystem(void) {
    return "com.forgelogkit.default";
}

static const char *_level_string(FLLogLevel level) {
    switch (level) {
        case FL_LOG_LEVEL_DEBUG: return "DEBUG";
        case FL_LOG_LEVEL_INFO:  return "INFO";
        case FL_LOG_LEVEL_WARN:  return "WARN";
        case FL_LOG_LEVEL_ERROR: return "ERROR";
        case FL_LOG_LEVEL_FAULT: return "FAULT";
        default:                 return "UNKNOWN";
    }
}

static os_log_type_t _type_for_level(FLLogLevel level) {
    switch (level) {
        case FL_LOG_LEVEL_DEBUG: return OS_LOG_TYPE_DEBUG;
        case FL_LOG_LEVEL_INFO:  return OS_LOG_TYPE_INFO;
        case FL_LOG_LEVEL_WARN:  return OS_LOG_TYPE_DEFAULT;
        case FL_LOG_LEVEL_ERROR: return OS_LOG_TYPE_ERROR;
        case FL_LOG_LEVEL_FAULT: return OS_LOG_TYPE_FAULT;
        default:                 return OS_LOG_TYPE_DEFAULT;
    }
}

static inline os_log_t _log(FLLogCHandle h) {
    return (h && h->log) ? h->log : OS_LOG_DEFAULT;
}

/* ================= lifecycle ================= */

FLLogCHandle FLLogCCreate(const char *subsystem, const char *category) {
    const char *sub = subsystem ? subsystem : FLDefaultSubsystem();
    const char *cat = category  ? category  : "Default";

    FLLogCHandle h = (FLLogCHandle)calloc(1, sizeof(*h));
    if (!h) return NULL;

    h->log = os_log_create(sub, cat);
    h->category = strdup(cat); /* own it */
    if (!h->category) {
        free(h);
        return NULL;
    }

    return h;
}

void FLLogCDestroy(FLLogCHandle h) {
    if (!h) return;
    free((void *)h->category);
    free(h);
}

/* ================= core emit ================= */

static void _emit(
    FLLogCHandle h,
    FLLogLevel level,
    const char *msg
) {
    if (!msg) return;

    char buf[FL_LOG_MAX_BUF];

    snprintf(
        buf,
        sizeof(buf),
        "[%s] [%s] %s",
        (h && h->category) ? h->category : "unknown",
        _level_string(level),
        msg
    );

    buf[sizeof(buf) - 1] = '\0';

    os_log_with_type(
        _log(h),
        _type_for_level(level),
        "%{public}s",
        buf
    );
}

/* ================= basic APIs ================= */

void FLLogCInfoH(FLLogCHandle h, const char *msg) {
    _emit(h, FL_LOG_LEVEL_INFO, msg);
}

void FLLogCDebugH(FLLogCHandle h, const char *msg) {
    _emit(h, FL_LOG_LEVEL_DEBUG, msg);
}

void FLLogCWarnH(FLLogCHandle h, const char *msg) {
    _emit(h, FL_LOG_LEVEL_WARN, msg);
}

void FLLogCErrorH(FLLogCHandle h, const char *msg) {
    _emit(h, FL_LOG_LEVEL_ERROR, msg);
}

void FLLogCFaultH(FLLogCHandle h, const char *msg) {
    _emit(h, FL_LOG_LEVEL_FAULT, msg);
}

/* ================= printf APIs ================= */

void FLLogCVLogfH(
    FLLogCHandle h,
    FLLogLevel level,
    const char *fmt,
    va_list ap
) {
    if (!fmt) return;

    char buf[FL_LOG_MAX_BUF];
    int n = snprintf(
        buf,
        sizeof(buf),
        "[%s] [%s] ",
        (h && h->category) ? h->category : "unknown",
        _level_string(level)
    );

    if (n <= 0 || n >= (int)sizeof(buf)) return;

    va_list ap_copy;
    va_copy(ap_copy, ap);
    vsnprintf(buf + n, sizeof(buf) - (size_t)n, fmt, ap_copy);
    va_end(ap_copy);

    buf[sizeof(buf) - 1] = '\0';

    os_log_with_type(
        _log(h),
        _type_for_level(level),
        "%{public}s",
        buf
    );
}

void FLLogCLogfH(
    FLLogCHandle h,
    FLLogLevel level,
    const char *fmt,
    ...
) {
    if (!fmt) return;

    va_list ap;
    va_start(ap, fmt);
    FLLogCVLogfH(h, level, fmt, ap);
    va_end(ap);
}
