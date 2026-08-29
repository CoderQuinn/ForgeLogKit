//
//  FLLogOC.h
//  ForgeLogKitOC
//
//  Created by MagicianQuinn on 2025/12/30.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void *FLLogOCHandle;

/// Process-wide default subsystem shared with the Swift and C APIs.
/// Changes affect only log handles created after the update.
FOUNDATION_EXPORT BOOL FLLogOCSetDefaultSubsystem(NSString *subsystem);
FOUNDATION_EXPORT NSString *FLLogOCDefaultSubsystem(void);

/// Create ObjC log instance
/// subsystem nil → default
FOUNDATION_EXPORT FLLogOCHandle FLLogOCCreate(
    NSString *_Nullable subsystem,
    NSString *_Nullable category
);

FOUNDATION_EXPORT void FLLogOCDestroy(FLLogOCHandle _Nullable h);

FOUNDATION_EXPORT void FLLogOCInfoH (FLLogOCHandle h, const char *msg);
FOUNDATION_EXPORT void FLLogOCDebugH(FLLogOCHandle h, const char *msg);
FOUNDATION_EXPORT void FLLogOCWarnH (FLLogOCHandle h, const char *msg);
FOUNDATION_EXPORT void FLLogOCErrorH(FLLogOCHandle h, const char *msg);
FOUNDATION_EXPORT void FLLogOCFaultH(FLLogOCHandle h, const char *msg);

typedef NS_ENUM(NSInteger, FLLogOCLevel) {
    FLLogOCLevelDebug = 0,
    FLLogOCLevelInfo = 1,
    FLLogOCLevelWarn = 2,
    FLLogOCLevelError = 3,
    FLLogOCLevelFault = 4,
};

typedef NS_ENUM(NSInteger, FLLogOCPrivacy) {
    FLLogOCPrivacyPrivate = 0,
    FLLogOCPrivacyPublic = 1,
};

FOUNDATION_EXPORT BOOL FLLogOCIsEnabledH(
    FLLogOCHandle _Nullable h,
    FLLogOCLevel level
);

FOUNDATION_EXPORT void FLLogOCLogH(
    FLLogOCHandle _Nullable h,
    FLLogOCLevel level,
    FLLogOCPrivacy privacy,
    NSString *_Nullable message
);

/// Emit a validated structured event using the shared stable field order.
/// component is required; the other fields are optional. Every supplied field
/// must contain 1...64 ASCII identifier bytes. Invalid input fails closed.
FOUNDATION_EXPORT void FLLogOCLogStructuredH(
    FLLogOCHandle _Nullable h,
    FLLogOCLevel level,
    FLLogOCPrivacy privacy,
    NSString *component,
    NSString *_Nullable phase,
    NSString *_Nullable errorCode,
    NSString *_Nullable correlationID,
    NSString *_Nullable message
);

NS_ASSUME_NONNULL_END
