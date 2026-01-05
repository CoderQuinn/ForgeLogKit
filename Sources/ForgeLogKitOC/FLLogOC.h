//
//  FLLogOC.h
//  ForgeLogKitOC
//
//  Created by MagicianQuinn on 2025/12/30.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void *FLLogOCHandle;

/// Create ObjC log instance
/// subsystem nil → default
FOUNDATION_EXPORT FLLogOCHandle FLLogOCCreate(
    NSString *_Nullable subsystem,
    NSString *_Nullable category
);

FOUNDATION_EXPORT void FLLogOCInfoH (FLLogOCHandle h, const char *msg);
FOUNDATION_EXPORT void FLLogOCDebugH(FLLogOCHandle h, const char *msg);
FOUNDATION_EXPORT void FLLogOCWarnH (FLLogOCHandle h, const char *msg);
FOUNDATION_EXPORT void FLLogOCErrorH(FLLogOCHandle h, const char *msg);

NS_ASSUME_NONNULL_END

