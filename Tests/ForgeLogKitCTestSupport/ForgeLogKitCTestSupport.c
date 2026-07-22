#include "ForgeLogKitCTestSupport.h"
#include <stdarg.h>
#include <stddef.h>
#include <string.h>

/* Hidden implementation seams from FLLogC.c. They are deliberately absent
 * from the product header and are consumed only by this test-support target. */
uint8_t FLLogCInternalTypeForLevel(FLLogLevel level);
int FLLogCInternalIsPublic(FLLogPrivacy privacy);
int FLLogCInternalFormatMessage(
    char *buf,
    size_t size,
    const char *category,
    FLLogLevel level,
    const char *msg
);
int FLLogCInternalVFormatMessage(
    char *buf,
    size_t size,
    const char *category,
    FLLogLevel level,
    const char *fmt,
    va_list ap
);

static void FLLogCTestResetEvent(FLLogCTestEvent *event) {
    if (event) memset(event, 0, sizeof(*event));
}

static void FLLogCTestSetRouting(
    FLLogCTestEvent *event,
    FLLogLevel level,
    FLLogPrivacy privacy
) {
    event->logType = FLLogCInternalTypeForLevel(level);
    event->isPublic = FLLogCInternalIsPublic(privacy);
}

static int FLLogCTestPrepareFormatted(
    const char *category,
    FLLogLevel level,
    FLLogPrivacy privacy,
    FLLogCTestEvent *event,
    const char *fmt,
    ...
) {
    FLLogCTestResetEvent(event);
    if (!event) return 0;

    va_list ap;
    va_start(ap, fmt);
    int result = FLLogCInternalVFormatMessage(
        event->message,
        sizeof(event->message),
        category,
        level,
        fmt,
        ap
    );
    va_end(ap);

    if (result) FLLogCTestSetRouting(event, level, privacy);
    return result;
}

void FLLogCTestFormatted(FLLogCHandle h) {
    FLLogCLogfH(h, FL_LOG_LEVEL_INFO, "Value: %d", 42);
    FLLogCLogfH(h, FL_LOG_LEVEL_DEBUG, "String: %s", "test");
    FLLogCLogfH(h, FL_LOG_LEVEL_WARN, "Float: %.2f", 3.14);
}

void FLLogCTestNullFormat(FLLogCHandle h) {
    FLLogCLogfH(h, FL_LOG_LEVEL_INFO, 0);
}

void FLLogCTestPrivateFormatted(FLLogCHandle h) {
    FLLogCLogfPrivacyH(
        h,
        FL_LOG_LEVEL_ERROR,
        FL_LOG_PRIVACY_PRIVATE,
        "error code=%d",
        42
    );
}

void FLLogCTestAllLevels(FLLogCHandle h) {
    FLLogCLogfH(h, FL_LOG_LEVEL_DEBUG, "Debug level test");
    FLLogCLogfH(h, FL_LOG_LEVEL_INFO, "Info level test");
    FLLogCLogfH(h, FL_LOG_LEVEL_WARN, "Warn level test");
    FLLogCLogfH(h, FL_LOG_LEVEL_ERROR, "Error level test");
    FLLogCLogfH(h, FL_LOG_LEVEL_FAULT, "Fault level test");
}

int FLLogCTestPrepareLiteral(
    const char *category,
    FLLogLevel level,
    FLLogPrivacy privacy,
    const char *message,
    FLLogCTestEvent *event
) {
    FLLogCTestResetEvent(event);
    if (!event) return 0;

    int result = FLLogCInternalFormatMessage(
        event->message,
        sizeof(event->message),
        category,
        level,
        message
    );
    if (result) FLLogCTestSetRouting(event, level, privacy);
    return result;
}

int FLLogCTestPrepareFormattedValues(
    const char *category,
    FLLogLevel level,
    FLLogPrivacy privacy,
    int count,
    const char *name,
    double ratio,
    FLLogCTestEvent *event
) {
    return FLLogCTestPrepareFormatted(
        category,
        level,
        privacy,
        event,
        "count=%d name=%s ratio=%.2f",
        count,
        name,
        ratio
    );
}

int FLLogCTestPrepareNullFormat(FLLogCTestEvent *event) {
    return FLLogCTestPrepareFormatted(
        "Null",
        FL_LOG_LEVEL_INFO,
        FL_LOG_PRIVACY_PUBLIC,
        event,
        NULL
    );
}

const char *FLLogCTestEventMessage(const FLLogCTestEvent *event) {
    return event ? event->message : NULL;
}

uint8_t FLLogCTestEventLogType(const FLLogCTestEvent *event) {
    return event ? event->logType : 0;
}

int FLLogCTestEventIsPublic(const FLLogCTestEvent *event) {
    return event ? event->isPublic : 0;
}
