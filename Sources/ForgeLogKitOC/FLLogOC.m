//
//  FLLogOC.m
//  ForgeLogKit
//
//  Created by MagicianQuinn on 2025/12/30.
//

#import "FLLogOC.h"
#import "FLLogC.h"

BOOL FLLogOCSetDefaultSubsystem(NSString *subsystem) {
    return FLLogCSetDefaultSubsystem(subsystem.UTF8String) != 0;
}

NSString *FLLogOCDefaultSubsystem(void) {
    size_t capacity = FLLogCGetDefaultSubsystem(NULL, 0);
    if (capacity == 0) return @"";

    NSMutableData *buffer = [NSMutableData dataWithLength:capacity];
    while (YES) {
        size_t requiredCapacity = FLLogCGetDefaultSubsystem(
            buffer.mutableBytes,
            buffer.length
        );
        if (requiredCapacity == 0) return @"";
        if (requiredCapacity <= buffer.length) {
            NSString *subsystem = [NSString stringWithUTF8String:buffer.bytes];
            return subsystem ?: @"";
        }
        buffer.length = requiredCapacity;
    }
}

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

void FLLogOCLogStructuredH(
    FLLogOCHandle h,
    FLLogOCLevel level,
    FLLogOCPrivacy privacy,
    NSString *component,
    NSString *phase,
    NSString *errorCode,
    NSString *correlationID,
    NSString *message
) {
    FLLogCFields fields = {
        .component = component.UTF8String,
        .phase = phase.UTF8String,
        .errorCode = errorCode.UTF8String,
        .correlationID = correlationID.UTF8String,
    };
    FLLogCLogStructuredH(
        (FLLogCHandle)h,
        (FLLogLevel)level,
        (FLLogPrivacy)privacy,
        &fields,
        message.UTF8String
    );
}
