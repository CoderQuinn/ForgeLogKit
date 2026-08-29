//
//  FLLogC.c
//  ForgeLogKitC
//
//  Created by MagicianQuinn on 2025/12/30.
//

#include "FLLogC.h"
#include <os/log.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#define FL_INTERNAL __attribute__((visibility("hidden")))
#define FL_LOG_FIELD_MAX_BYTES 64
#define FL_LOG_FIELDS_MAX_BUF 384

/* ================= internal ================= */

struct FLLogCHandle {
    os_log_t log;
    const char *category;   /* owned copy */
};

static const char FLBuiltInDefaultSubsystem[] = "com.forgelogkit.default";
static pthread_mutex_t FLDefaultSubsystemLock = PTHREAD_MUTEX_INITIALIZER;
static char *FLConfiguredDefaultSubsystem;

static const char *FLDefaultSubsystemLocked(void) {
    return FLConfiguredDefaultSubsystem
        ? FLConfiguredDefaultSubsystem
        : FLBuiltInDefaultSubsystem;
}

static char *FLCopyDefaultSubsystem(void) {
    if (pthread_mutex_lock(&FLDefaultSubsystemLock) != 0) return NULL;
    char *copy = strdup(FLDefaultSubsystemLocked());
    pthread_mutex_unlock(&FLDefaultSubsystemLock);
    return copy;
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

static inline int _is_public(FLLogPrivacy privacy) {
    return privacy == FL_LOG_PRIVACY_PUBLIC;
}

static int FLIsFieldByte(unsigned char byte) {
    return
        (byte >= 'A' && byte <= 'Z') ||
        (byte >= 'a' && byte <= 'z') ||
        (byte >= '0' && byte <= '9') ||
        byte == '.' || byte == '_' || byte == ':' || byte == '-';
}

static int FLIsValidField(const char *value) {
    if (!value) return 0;

    size_t length = strnlen(value, FL_LOG_FIELD_MAX_BYTES + 1);
    if (length == 0 || length > FL_LOG_FIELD_MAX_BYTES) return 0;
    for (size_t index = 0; index < length; index++) {
        if (!FLIsFieldByte((unsigned char)value[index])) return 0;
    }
    return 1;
}

static int FLAppendField(
    char *buffer,
    size_t capacity,
    size_t *length,
    const char *name,
    const char *value
) {
    if (!buffer || !length || !name || !value || *length >= capacity) return 0;

    int written = snprintf(
        buffer + *length,
        capacity - *length,
        "[%s=%s]",
        name,
        value
    );
    if (written < 0 || (size_t)written >= capacity - *length) return 0;
    *length += (size_t)written;
    return 1;
}

static int FLFormatFields(
    char *buffer,
    size_t capacity,
    const FLLogCFields *fields
) {
    if (!buffer || capacity == 0 || !fields ||
        !FLIsValidField(fields->component)) return 0;
    if ((fields->phase && !FLIsValidField(fields->phase)) ||
        (fields->errorCode && !FLIsValidField(fields->errorCode)) ||
        (fields->correlationID && !FLIsValidField(fields->correlationID))) {
        return 0;
    }

    size_t length = 0;
    if (!FLAppendField(
        buffer,
        capacity,
        &length,
        "component",
        fields->component
    )) return 0;
    if (fields->phase && !FLAppendField(
        buffer,
        capacity,
        &length,
        "phase",
        fields->phase
    )) return 0;
    if (fields->errorCode && !FLAppendField(
        buffer,
        capacity,
        &length,
        "error_code",
        fields->errorCode
    )) return 0;
    if (fields->correlationID && !FLAppendField(
        buffer,
        capacity,
        &length,
        "correlation_id",
        fields->correlationID
    )) return 0;

    if (length + 1 >= capacity) return 0;
    buffer[length] = ' ';
    buffer[length + 1] = '\0';
    return 1;
}

static size_t FLFormatStructuredMessage(
    char *buffer,
    size_t capacity,
    const char *category,
    FLLogLevel level,
    const FLLogCFields *fields,
    const char *message
) {
    if (!message || !fields) {
        if (buffer && capacity > 0) buffer[0] = '\0';
        return 0;
    }

    char formattedFields[FL_LOG_FIELDS_MAX_BUF] = "";
    if (!FLFormatFields(
        formattedFields,
        sizeof(formattedFields),
        fields
    )) {
        if (buffer && capacity > 0) buffer[0] = '\0';
        return 0;
    }

    size_t redactedCapacity = FLLogCRedactMessage(message, NULL, 0);
    if (redactedCapacity == 0) {
        if (buffer && capacity > 0) buffer[0] = '\0';
        return 0;
    }

    int prefixLength = snprintf(
        NULL,
        0,
        "[%s] [%s] %s",
        category ? category : "unknown",
        _level_string(level),
        formattedFields
    );
    if (prefixLength < 0 ||
        redactedCapacity > SIZE_MAX - (size_t)prefixLength) {
        if (buffer && capacity > 0) buffer[0] = '\0';
        return 0;
    }
    size_t requiredCapacity = (size_t)prefixLength + redactedCapacity;
    if (!buffer || capacity == 0) return requiredCapacity;

    char stackRedacted[FL_LOG_MAX_BUF];
    char *redacted = stackRedacted;
    if (redactedCapacity > sizeof(stackRedacted)) {
        redacted = malloc(redactedCapacity);
        if (!redacted) {
            buffer[0] = '\0';
            return 0;
        }
    }

    size_t returnedCapacity = FLLogCRedactMessage(
        message,
        redacted,
        redactedCapacity > sizeof(stackRedacted)
            ? redactedCapacity
            : sizeof(stackRedacted)
    );
    if (returnedCapacity != redactedCapacity) {
        if (redacted != stackRedacted) free(redacted);
        buffer[0] = '\0';
        return 0;
    }

    int written = snprintf(
        buffer,
        capacity,
        "[%s] [%s] %s%s",
        category ? category : "unknown",
        _level_string(level),
        formattedFields,
        redacted
    );
    if (written < 0 || (size_t)written + 1 != requiredCapacity) {
        if (redacted != stackRedacted) free(redacted);
        buffer[0] = '\0';
        return 0;
    }
    if (redacted != stackRedacted) free(redacted);
    buffer[capacity - 1] = '\0';
    return requiredCapacity;
}

/* These hidden functions are shared by production emission and the C test
 * support target. They intentionally do not appear in the public header. */

FL_INTERNAL unsigned char FLLogCInternalTypeForLevel(FLLogLevel level) {
    return (unsigned char)_type_for_level(level);
}

FL_INTERNAL int FLLogCInternalIsPublic(FLLogPrivacy privacy) {
    return _is_public(privacy);
}

FL_INTERNAL int FLLogCInternalFormatMessage(
    char *buf,
    unsigned long size,
    const char *category,
    FLLogLevel level,
    const char *msg
) {
    if (!buf || size == 0 || !msg) return 0;

    char redacted[FL_LOG_MAX_BUF];
    if (FLLogCRedactMessage(msg, redacted, sizeof(redacted)) == 0) return 0;

    int n = snprintf(
        buf,
        size,
        "[%s] [%s] %s",
        category ? category : "unknown",
        _level_string(level),
        redacted
    );

    buf[size - 1] = '\0';
    return n >= 0;
}

FL_INTERNAL int FLLogCInternalVFormatMessage(
    char *buf,
    unsigned long size,
    const char *category,
    FLLogLevel level,
    const char *fmt,
    va_list ap
) {
    if (!buf || size == 0 || !fmt) return 0;

    char message[FL_LOG_MAX_BUF];

    va_list ap_copy;
    va_copy(ap_copy, ap);
    int message_length = vsnprintf(
        message,
        sizeof(message),
        fmt,
        ap_copy
    );
    va_end(ap_copy);

    if (message_length < 0 || message_length >= (int)sizeof(message)) return 0;

    char redacted[FL_LOG_MAX_BUF];
    if (FLLogCRedactMessage(message, redacted, sizeof(redacted)) == 0) return 0;

    int n = snprintf(
        buf,
        size,
        "[%s] [%s] %s",
        category ? category : "unknown",
        _level_string(level),
        redacted
    );

    buf[size - 1] = '\0';
    return n >= 0 && n < (int)size;
}

/* ================= lifecycle ================= */

int FLLogCSetDefaultSubsystem(const char *subsystem) {
    if (!subsystem) return 0;

    char *copy = strdup(subsystem);
    if (!copy) return 0;
    if (pthread_mutex_lock(&FLDefaultSubsystemLock) != 0) {
        free(copy);
        return 0;
    }

    char *previous = FLConfiguredDefaultSubsystem;
    FLConfiguredDefaultSubsystem = copy;
    pthread_mutex_unlock(&FLDefaultSubsystemLock);
    free(previous);
    return 1;
}

size_t FLLogCFormatStructuredMessage(
    const char *category,
    FLLogLevel level,
    const FLLogCFields *fields,
    const char *message,
    char *buffer,
    size_t capacity
) {
    return FLFormatStructuredMessage(
        buffer,
        capacity,
        category,
        level,
        fields,
        message
    );
}

size_t FLLogCGetDefaultSubsystem(char *buffer, size_t capacity) {
    if (pthread_mutex_lock(&FLDefaultSubsystemLock) != 0) return 0;

    const char *subsystem = FLDefaultSubsystemLocked();
    int writtenLength = buffer && capacity > 0
        ? snprintf(buffer, capacity, "%s", subsystem)
        : snprintf(NULL, 0, "%s", subsystem);

    pthread_mutex_unlock(&FLDefaultSubsystemLock);
    return writtenLength < 0 ? 0 : (size_t)writtenLength + 1;
}

FLLogCHandle FLLogCCreate(const char *subsystem, const char *category) {
    char *defaultSubsystem = subsystem ? NULL : FLCopyDefaultSubsystem();
    if (!subsystem && !defaultSubsystem) return NULL;

    const char *sub = subsystem ? subsystem : defaultSubsystem;
    const char *cat = category  ? category  : "Default";

    FLLogCHandle h = (FLLogCHandle)calloc(1, sizeof(*h));
    if (!h) {
        free(defaultSubsystem);
        return NULL;
    }

    h->log = os_log_create(sub, cat);
    free(defaultSubsystem);
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

static void FLEmitPrepared(
    FLLogCHandle h,
    FLLogLevel level,
    FLLogPrivacy privacy,
    const char *message
) {
    if (FLLogCInternalIsPublic(privacy)) {
        os_log_with_type(
            _log(h),
            (os_log_type_t)FLLogCInternalTypeForLevel(level),
            "%{public}s",
            message
        );
    } else {
        os_log_with_type(
            _log(h),
            (os_log_type_t)FLLogCInternalTypeForLevel(level),
            "%{private}s",
            message
        );
    }
}

static void _emit(
    FLLogCHandle h,
    FLLogLevel level,
    FLLogPrivacy privacy,
    const char *msg
) {
    char buf[FL_LOG_MAX_BUF];
    if (!FLLogCInternalFormatMessage(
        buf,
        sizeof(buf),
        (h && h->category) ? h->category : "unknown",
        level,
        msg
    )) return;

    FLEmitPrepared(h, level, privacy, buf);
}

static void _emit_structured(
    FLLogCHandle h,
    FLLogLevel level,
    FLLogPrivacy privacy,
    const FLLogCFields *fields,
    const char *msg
) {
    char buf[FL_LOG_MAX_BUF];
    if (FLLogCFormatStructuredMessage(
        (h && h->category) ? h->category : "unknown",
        level,
        fields,
        msg,
        buf,
        sizeof(buf)
    ) == 0) return;

    FLEmitPrepared(h, level, privacy, buf);
}

/* ================= basic APIs ================= */

void FLLogCInfoH(FLLogCHandle h, const char *msg) {
    _emit(h, FL_LOG_LEVEL_INFO, FL_LOG_PRIVACY_PUBLIC, msg);
}

void FLLogCDebugH(FLLogCHandle h, const char *msg) {
    _emit(h, FL_LOG_LEVEL_DEBUG, FL_LOG_PRIVACY_PUBLIC, msg);
}

void FLLogCWarnH(FLLogCHandle h, const char *msg) {
    _emit(h, FL_LOG_LEVEL_WARN, FL_LOG_PRIVACY_PUBLIC, msg);
}

void FLLogCErrorH(FLLogCHandle h, const char *msg) {
    _emit(h, FL_LOG_LEVEL_ERROR, FL_LOG_PRIVACY_PUBLIC, msg);
}

void FLLogCFaultH(FLLogCHandle h, const char *msg) {
    _emit(h, FL_LOG_LEVEL_FAULT, FL_LOG_PRIVACY_PUBLIC, msg);
}

int FLLogCIsEnabledH(FLLogCHandle h, FLLogLevel level) {
    return os_log_type_enabled(_log(h), _type_for_level(level));
}

void FLLogCLogH(
    FLLogCHandle h,
    FLLogLevel level,
    FLLogPrivacy privacy,
    const char *msg
) {
    _emit(h, level, privacy, msg);
}

void FLLogCLogStructuredH(
    FLLogCHandle h,
    FLLogLevel level,
    FLLogPrivacy privacy,
    const FLLogCFields *fields,
    const char *msg
) {
    _emit_structured(h, level, privacy, fields, msg);
}

/* ================= printf APIs ================= */

void FLLogCVLogfH(
    FLLogCHandle h,
    FLLogLevel level,
    const char *fmt,
    va_list ap
) {
    FLLogCVLogfPrivacyH(
        h,
        level,
        FL_LOG_PRIVACY_PUBLIC,
        fmt,
        ap
    );
}

void FLLogCVLogfPrivacyH(
    FLLogCHandle h,
    FLLogLevel level,
    FLLogPrivacy privacy,
    const char *fmt,
    va_list ap
) {
    char buf[FL_LOG_MAX_BUF];
    if (!FLLogCInternalVFormatMessage(
        buf,
        sizeof(buf),
        (h && h->category) ? h->category : "unknown",
        level,
        fmt,
        ap
    )) return;

    if (FLLogCInternalIsPublic(privacy)) {
        os_log_with_type(
            _log(h),
            (os_log_type_t)FLLogCInternalTypeForLevel(level),
            "%{public}s",
            buf
        );
    } else {
        os_log_with_type(
            _log(h),
            (os_log_type_t)FLLogCInternalTypeForLevel(level),
            "%{private}s",
            buf
        );
    }
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

void FLLogCLogfPrivacyH(
    FLLogCHandle h,
    FLLogLevel level,
    FLLogPrivacy privacy,
    const char *fmt,
    ...
) {
    if (!fmt) return;

    va_list ap;
    va_start(ap, fmt);
    FLLogCVLogfPrivacyH(h, level, privacy, fmt, ap);
    va_end(ap);
}
