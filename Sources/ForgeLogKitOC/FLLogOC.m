//
//  FLLogOC.m
//  ForgeLogKit
//
//  Created by MagicianQuinn on 2025/12/30.
//

#import "FLLogOC.h"
#import "FLLogC.h"

FLLogOCHandle FLLogOCCreate(
    NSString *subsystem,
    NSString *category
) {
    return FLLogCCreate(
        subsystem.UTF8String,
        category.UTF8String
    );
}

void FLLogOCDestroy(FLLogOCHandle h) {
    FLLogCDestroy((FLLogCHandle)h);
}

void FLLogOCInfoH(FLLogOCHandle h, const char *msg) {
    FLLogCInfoH((FLLogCHandle)h, msg);
}

void FLLogOCDebugH(FLLogOCHandle h, const char *msg) {
    FLLogCDebugH((FLLogCHandle)h, msg);
}

void FLLogOCWarnH(FLLogOCHandle h, const char *msg) {
    FLLogCWarnH((FLLogCHandle)h, msg);
}

void FLLogOCErrorH(FLLogOCHandle h, const char *msg) {
    FLLogCErrorH((FLLogCHandle)h, msg);
}

void FLLogOCFaultH(FLLogOCHandle h, const char *msg) {
    FLLogCFaultH((FLLogCHandle)h, msg);
}

BOOL FLLogOCIsEnabledH(FLLogOCHandle h, FLLogOCLevel level) {
    return FLLogCIsEnabledH((FLLogCHandle)h, (FLLogLevel)level) != 0;
}

void FLLogOCLogH(
    FLLogOCHandle h,
    FLLogOCLevel level,
    FLLogOCPrivacy privacy,
    NSString *message
) {
    FLLogCLogH(
        (FLLogCHandle)h,
        (FLLogLevel)level,
        (FLLogPrivacy)privacy,
        message.UTF8String
    );
}
