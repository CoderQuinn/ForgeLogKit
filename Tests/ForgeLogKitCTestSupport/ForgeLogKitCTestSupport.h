#pragma once

#include "FLLogC.h"

#ifdef __cplusplus
extern "C" {
#endif

void FLLogCTestFormatted(FLLogCHandle h);
void FLLogCTestNullFormat(FLLogCHandle h);
void FLLogCTestPrivateFormatted(FLLogCHandle h);
void FLLogCTestAllLevels(FLLogCHandle h);

#ifdef __cplusplus
}
#endif
