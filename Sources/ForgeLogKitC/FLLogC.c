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

/* ---------------- 内部结构 ---------------- */

struct FLLogCHandle {
    os_log_t log;
};

static const char *FLDefaultSubsystem(void) {
    return "com.forgelogkit.default";
}

/* ---------------- level → os_log_type ---------------- */

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

static inline const char *_safe(const char *s) {
    return s ? s : "";
}

/* ---------------- lifecycle ---------------- */

FLLogCHandle FLLogCCreate(const char *subsystem, const char *category) {
    const char *sub = subsystem ? subsystem : FLDefaultSubsystem();
    const char *cat = category  ? category  : "Default";

    FLLogCHandle h = (FLLogCHandle)malloc(sizeof(*h));
    if (!h) return NULL;

    /*
     * os_log_create 不会返回 NULL
     * 但为了防御性编程，_log() 里仍然有 OS_LOG_DEFAULT 兜底
     */
    h->log = os_log_create(sub, cat);
    return h;
}

void FLLogCDestroy(FLLogCHandle h) {
    if (!h) return;
    /* os_log_t 不需要释放 */
    free(h);
}

/* ---------------- 基础字符串接口 ---------------- */

void FLLogCInfoH(FLLogCHandle h, const char *msg) {
    os_log_with_type(_log(h), OS_LOG_TYPE_INFO, "%{public}s", _safe(msg));
}

void FLLogCDebugH(FLLogCHandle h, const char *msg) {
    os_log_with_type(_log(h), OS_LOG_TYPE_DEBUG, "%{public}s", _safe(msg));
}

void FLLogCWarnH(FLLogCHandle h, const char *msg) {
    os_log_with_type(_log(h), OS_LOG_TYPE_DEFAULT, "%{public}s", _safe(msg));
}

void FLLogCErrorH(FLLogCHandle h, const char *msg) {
    os_log_with_type(_log(h), OS_LOG_TYPE_ERROR, "%{public}s", _safe(msg));
}

void FLLogCFaultH(FLLogCHandle h, const char *msg) {
    os_log_with_type(_log(h), OS_LOG_TYPE_FAULT, "%{public}s", _safe(msg));
}

/* ---------------- printf / vprintf ---------------- */

/*
 * 这是整个库最关键的函数：
 *
 * - fmt 不是常量字符串（lwIP / tun / 上层都会传动态 format）
 * - os_log 要求 format 必须是编译期常量
 *
 * 解决方案：
 *   1. vsnprintf → 栈上 buf
 *   2. os_log("%{public}s", buf)
 */
void FLLogCVLogfH(
    FLLogCHandle h,
    FLLogLevel level,
    const char *fmt,
    va_list ap
) {
    if (!fmt) return;

    char buf[FL_LOG_MAX_BUF];
    buf[0] = '\0';

    /*
     * 防御：明显非法的 fmt 指针
     * 统一走 buffer → "%{public}s" 路径
     */
    if ((uintptr_t)fmt < 0x1000 || !memchr(fmt, '\0', 4096)) {
        snprintf(
            buf,
            sizeof(buf),
            "FLLogC: invalid fmt pointer %p",
            fmt
        );
        buf[sizeof(buf) - 1] = '\0';

        os_log_with_type(
            _log(h),
            OS_LOG_TYPE_ERROR,
            "%{public}s",
            buf
        );
        return;
    }
    
    /*
     * va_list 只能使用一次，必须 copy
     */
    va_list ap_copy;
    va_copy(ap_copy, ap);
    int n = vsnprintf(buf, sizeof(buf), fmt, ap_copy);
    va_end(ap_copy);

    if (n <= 0) return;

    /* 强制 NUL 结尾，防止实现差异 */
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

