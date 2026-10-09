#import "FLLogOC.h"
#include "FLLogC.h"
#import "Capture.h"
#include <assert.h>
#include <string.h>

static NSString *captured;
static const char *routing;
static unsigned calls;

void FLTestCapture(os_log_t log, os_log_type_t type, const char *format, const char *message) {
    (void)log;
    (void)type;
    captured = [NSString stringWithUTF8String:message];
    routing = format;
    calls++;
}

int main(void) {
    @autoreleasepool {
        FLLogOCHandle handle = FLLogOCCreate(@"com.test.aliases", @"Aliases");
        assert(handle);
        NSArray<NSString *> *aliases = @[
            @"PrivateKey", @"private_key", @"private-key",
            @"PresharedKey", @"preshared_key", @"preshared-key",
            @"HeaderProtectionKey", @"header_protection_key", @"header-protection-key"
        ];
        const char *levels[] = {"DEBUG", "INFO", "WARN", "ERROR", "FAULT"};
        void (*convenience[])(FLLogOCHandle, const char *) = {
            FLLogOCDebugH, FLLogOCInfoH, FLLogOCWarnH, FLLogOCErrorH, FLLogOCFaultH
        };
        unsigned verified = 0;
        for (NSString *spelling in aliases) {
          for (NSString *alias in @[spelling, spelling.uppercaseString, spelling.lowercaseString]) {
            NSArray<NSArray<NSString *> *> *samples = @[
                @[[NSString stringWithFormat:@"%@=synthetic-objc-canary+/==", alias],
                  [NSString stringWithFormat:@"%@=<redacted>", alias]],
                @[[NSString stringWithFormat:@"{\"%@\":\"synthetic-objc-canary+/==\",\"ready\":true}", alias],
                  [NSString stringWithFormat:@"{\"%@\":\"<redacted>\",\"ready\":true}", alias]],
                @[[NSString stringWithFormat:@"{\"%@\":\n\"synthetic-objc-canary+/==\"}", alias],
                  [NSString stringWithFormat:@"{\"%@\":\n\"<redacted>\"}", alias]],
                @[[NSString stringWithFormat:@"{\"%@\"\n:\"synthetic-objc-canary+/==\"}", alias],
                  [NSString stringWithFormat:@"{\"%@\"\n:\"<redacted>\"}", alias]],
                @[[NSString stringWithFormat:@"{\"%@\":\r\n\"synthetic-objc-canary+/==\"}", alias],
                  [NSString stringWithFormat:@"{\"%@\":\r\n\"<redacted>\"}", alias]],
                @[[NSString stringWithFormat:@"{\"%@\"\r\n:\"synthetic-objc-canary+/==\"}", alias],
                  [NSString stringWithFormat:@"{\"%@\"\r\n:\"<redacted>\"}", alias]],
                @[[NSString stringWithFormat:@"%@='synthetic-objc-canary escaped\\' tail'", alias],
                  [NSString stringWithFormat:@"%@='<redacted>'", alias]],
                @[[NSString stringWithFormat:@"%@=\"synthetic-objc-canary unterminated\nrest", alias],
                  [NSString stringWithFormat:@"%@=\"<redacted>", alias]],
                @[[NSString stringWithFormat:@"%@Count=7", alias],
                  [NSString stringWithFormat:@"%@Count=7", alias]],
                @[[NSString stringWithFormat:@"%@:\nready=true", alias],
                  [NSString stringWithFormat:@"%@:<redacted>\nready=true", alias]],
                @[[NSString stringWithFormat:@"%@\n:ready=true", alias],
                  [NSString stringWithFormat:@"%@\n:ready=true", alias]],
                @[[NSString stringWithFormat:@"\"%@\"=\nready=true", alias],
                  [NSString stringWithFormat:@"\"%@\"=<redacted>\nready=true", alias]],
            ];
          for (NSArray<NSString *> *sample in samples) {
            NSString *input = sample[0];
            char redacted[512];
            size_t required = FLLogCRedactMessage(input.UTF8String, redacted, sizeof(redacted));
            assert(required > 0 && required <= sizeof(redacted));
            assert([[NSString stringWithUTF8String:redacted] isEqualToString:sample[1]]);
            NSData *expectedBytes = [sample[1] dataUsingEncoding:NSUTF8StringEncoding];
            assert(required == expectedBytes.length + 1);
            for (size_t capacity = 0; capacity <= expectedBytes.length + 2; capacity++) {
                char truncated[512];
                memset(truncated, 0x7f, sizeof(truncated));
                size_t returned = FLLogCRedactMessage(input.UTF8String, truncated, capacity);
                assert(returned == required);
                if (capacity > 0) {
                    size_t prefixLength = MIN(expectedBytes.length, capacity - 1);
                    assert(memcmp(truncated, expectedBytes.bytes, prefixLength) == 0);
                    assert(truncated[prefixLength] == '\0');
                }
            }
            for (int level = 0; level < 5; level++) {
                NSString *expected = [NSString stringWithFormat:@"[Aliases] [%s] %@", levels[level], sample[1]];
                calls = 0;
                convenience[level](handle, input.UTF8String);
                assert(calls == 1 && [captured isEqualToString:expected]);
                assert(strcmp(routing, "%{public}s") == 0);
                verified++;
                for (int privacy = 0; privacy < 2; privacy++) {
                    calls = 0;
                    FLLogOCLogH(handle, level, privacy, input);
                    assert(calls == 1 && [captured isEqualToString:expected]);
                    assert(strcmp(routing, privacy ? "%{public}s" : "%{private}s") == 0);
                    verified++;
                    calls = 0;
                    FLLogOCLogStructuredH(handle, level, privacy, @"runtime", nil, nil, nil, input);
                    NSString *structured = [NSString stringWithFormat:@"[Aliases] [%s] [component=runtime] %@", levels[level], sample[1]];
                    assert(calls == 1 && [captured isEqualToString:structured]);
                    assert(strcmp(routing, privacy ? "%{public}s" : "%{private}s") == 0);
                    verified++;
                }
            }
          }
          }
        }
        FLLogOCDestroy(handle);
        printf("Objective-C actual adapter/C redactor: %u captured emissions verified\n", verified);
    }
    return 0;
}
