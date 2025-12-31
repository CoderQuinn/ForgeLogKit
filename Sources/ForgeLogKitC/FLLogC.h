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
 * 编译期可配置日志 buffer 大小
 *
 * 默认 1024
 * 外部可通过 -DFL_LOG_MAX_BUF=1024 覆盖
 *
 * 必须是编译期常量（用于栈数组）
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
 * 创建日志实例
 *
 * subsystem == NULL → 使用默认 subsystem
 * category  == NULL → 使用 "Default"
 */
FLLogCHandle FLLogCCreate(const char *subsystem, const char *category);

/*
 * 释放 handle（os_log_t 无需释放，仅 free handle）
 */
void FLLogCDestroy(FLLogCHandle h);

/* -------- 基础字符串接口 -------- */

void FLLogCInfoH (FLLogCHandle h, const char *msg);
void FLLogCDebugH(FLLogCHandle h, const char *msg);
void FLLogCWarnH (FLLogCHandle h, const char *msg);
void FLLogCErrorH(FLLogCHandle h, const char *msg);
void FLLogCFaultH(FLLogCHandle h, const char *msg);

/* -------- printf / vprintf 接口 --------
 *
 * 注意：
 * os_log 的 format 必须是编译期常量字符串
 * 因此内部实现会：
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
