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
