//
//  FLLogC.h
//  ForgeLogKitC
//
//  Created by MagicianQuinn on 2025/12/30.
//
//  Pure C os_log wrapper (no lwIP / no tun / no platform policy)
//

#pragma once
#include <stddef.h>
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

typedef enum {
    FL_LOG_PRIVACY_PRIVATE = 0,
    FL_LOG_PRIVACY_PUBLIC  = 1,
} FLLogPrivacy;

/*
 * Stable structured fields shared by the Swift, C, and Objective-C APIs.
 *
 * component is required. The remaining fields are optional. Every supplied
 * value must contain 1...64 ASCII identifier bytes from A-Z, a-z, 0-9, '.',
 * '_', ':', or '-'. This deliberately excludes whitespace and delimiters so
 * the serialized representation cannot be made ambiguous by caller input.
 */
typedef struct {
    const char *component;
    const char *phase;
    const char *errorCode;
    const char *correlationID;
} FLLogCFields;

/*
 * Redact recognized secret-bearing fields before storage or emission.
 *
 * The return value is the required capacity including the trailing NUL byte.
 * Passing NULL for buffer performs a size query. A non-NULL buffer is always
 * NUL-terminated when capacity is greater than zero. Input and output must not
 * overlap. A NULL message or one without a NUL byte before the 64 KiB scan
 * bound returns zero.
 */
size_t FLLogCRedactMessage(
    const char *message,
    char *buffer,
    size_t capacity
);

/*
 * Format one structured event using this stable field order:
 *
 * [category] [LEVEL] [component=...][phase=...][error_code=...]
 * [correlation_id=...] message
 *
 * Optional fields that are NULL are omitted. The message is redacted before
 * formatting. The return value is the required capacity including the
 * trailing NUL byte. Passing NULL for buffer performs a size query. A
 * non-NULL buffer is always NUL-terminated when capacity is greater than zero.
 * Invalid fields or messages fail closed and return zero.
 */
size_t FLLogCFormatStructuredMessage(
    const char *category,
    FLLogLevel level,
    const FLLogCFields *fields,
    const char *message,
    char *buffer,
    size_t capacity
);

/*
 * Process-wide default subsystem shared by the Swift, C, and Objective-C APIs.
 *
 * Set accepts a non-NULL UTF-8 string and returns non-zero on success. Get
 * returns the required buffer size, including the trailing NUL byte, and
 * writes a NUL-terminated value when buffer is non-NULL and capacity is
 * greater than zero. Access is thread-safe. Changes apply only to handles
 * created after the update.
 */
int FLLogCSetDefaultSubsystem(const char *subsystem);
size_t FLLogCGetDefaultSubsystem(char *buffer, size_t capacity);

/*
 * Create a log handle
 *
 * subsystem == NULL → use default subsystem
 * category  == NULL → use "Default"
 */
FLLogCHandle FLLogCCreate(const char *subsystem, const char *category);

/*
 * Destroy one exclusively owned handle.
 *
 * Calls that borrow the handle before registry removal finish concurrently;
 * destroy waits for those calls before reclaiming the wrapper. Racing calls
 * that reach the registry after removal fail closed. The owner must prevent
 * new calls from starting once destruction begins, call destroy exactly once,
 * and never reuse the handle value after this function returns. Passing NULL
 * remains a no-op.
 */
void FLLogCDestroy(FLLogCHandle h);

/* -------- Basic string APIs -------- */

void FLLogCInfoH (FLLogCHandle h, const char *msg);
void FLLogCDebugH(FLLogCHandle h, const char *msg);
void FLLogCWarnH (FLLogCHandle h, const char *msg);
void FLLogCErrorH(FLLogCHandle h, const char *msg);
void FLLogCFaultH(FLLogCHandle h, const char *msg);

/* Returns non-zero when Unified Logging enables the requested level. */
int FLLogCIsEnabledH(FLLogCHandle h, FLLogLevel level);

/* Explicit level and privacy API. Invalid privacy values fail closed. */
void FLLogCLogH(
    FLLogCHandle h,
    FLLogLevel level,
    FLLogPrivacy privacy,
    const char *msg
);

/* Emit a validated structured event. Invalid inputs fail closed. */
void FLLogCLogStructuredH(
    FLLogCHandle h,
    FLLogLevel level,
    FLLogPrivacy privacy,
    const FLLogCFields *fields,
    const char *msg
);

/* -------- printf / vprintf APIs --------
 *
 * Note:
 * os_log format must be a compile-time constant string.
 * Therefore the implementation does:
 *   vsnprintf → char buf[FL_LOG_MAX_BUF]
 *   os_log("%{public}s", buf)
 * Formatted messages larger than FL_LOG_MAX_BUF fail closed without emission.
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

void FLLogCLogfPrivacyH(
    FLLogCHandle h,
    FLLogLevel level,
    FLLogPrivacy privacy,
    const char *fmt,
    ...
) __attribute__((format(printf, 4, 5)));

void FLLogCVLogfPrivacyH(
    FLLogCHandle h,
    FLLogLevel level,
    FLLogPrivacy privacy,
    const char *fmt,
    va_list ap
);

#ifdef __cplusplus
}
#endif
