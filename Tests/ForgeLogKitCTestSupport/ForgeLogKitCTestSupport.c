#include "ForgeLogKitCTestSupport.h"
#include <stddef.h>

void FLLogCTestFormatted(FLLogCHandle h) {
    FLLogCLogfH(h, FL_LOG_LEVEL_INFO, "Value: %d", 42);
    FLLogCLogfH(h, FL_LOG_LEVEL_DEBUG, "String: %s", "test");
    FLLogCLogfH(h, FL_LOG_LEVEL_WARN, "Float: %.2f", 3.14);
}

void FLLogCTestNullFormat(FLLogCHandle h) {
    FLLogCLogfH(h, FL_LOG_LEVEL_INFO, NULL);
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
