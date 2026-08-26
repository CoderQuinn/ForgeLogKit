#pragma once

#include "FLLogC.h"

#ifdef __cplusplus
extern "C" {
#endif

void FLLogCTestFormatted(FLLogCHandle h);
void FLLogCTestNullFormat(FLLogCHandle h);
void FLLogCTestPrivateFormatted(FLLogCHandle h);
void FLLogCTestAllLevels(FLLogCHandle h);

typedef struct {
    char message[FL_LOG_MAX_BUF];
    unsigned char logType;
    int isPublic;
} FLLogCTestEvent;

int FLLogCTestPrepareLiteral(
    const char *category,
    FLLogLevel level,
    FLLogPrivacy privacy,
    const char *message,
    FLLogCTestEvent *event
);

int FLLogCTestPrepareFormattedValues(
    const char *category,
    FLLogLevel level,
    FLLogPrivacy privacy,
    int count,
    const char *name,
    double ratio,
    FLLogCTestEvent *event
);

int FLLogCTestPrepareNullFormat(FLLogCTestEvent *event);
int FLLogCTestRejectsInvalidLiteralInputs(void);
int FLLogCTestRejectsTinyFormattedBuffer(void);
const char *FLLogCTestEventMessage(const FLLogCTestEvent *event);
unsigned char FLLogCTestEventLogType(const FLLogCTestEvent *event);
int FLLogCTestEventIsPublic(const FLLogCTestEvent *event);

#ifdef __cplusplus
}
#endif
