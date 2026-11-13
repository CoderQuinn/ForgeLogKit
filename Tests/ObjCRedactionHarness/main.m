#import "FLLogOC.h"
#include "FLLogC.h"
#import "Capture.h"
#include <assert.h>
#include <string.h>

static NSString *captured;
static NSData *capturedBytes;
static const char *routing;
static unsigned calls;

void FLTestCapture(os_log_t log, os_log_type_t type, const char *format, const char *message) {
    (void)log;
    (void)type;
    capturedBytes = [NSData dataWithBytes:message length:strlen(message)];
    captured = [NSString stringWithUTF8String:message];
    routing = format;
    calls++;
}

static void expectEmission(NSString *expected, const char *privacy) {
    NSData *bytes = [expected dataUsingEncoding:NSUTF8StringEncoding];
    assert(calls == 1);
    assert([capturedBytes isEqualToData:bytes]);
    assert(strcmp(routing, privacy) == 0);
}

static unsigned verifyCanary(FLLogOCHandle handle, NSString *input,
                             NSString *expected, NSArray<NSString *> *canaries) {
    NSData *expectedBytes = [expected dataUsingEncoding:NSUTF8StringEncoding];
    size_t capacity = FLLogCRedactMessage(input.UTF8String, NULL, 0);
    assert(capacity == expectedBytes.length + 1);
    NSMutableData *buffer = [NSMutableData dataWithLength:capacity];
    assert(FLLogCRedactMessage(input.UTF8String, buffer.mutableBytes, capacity) == capacity);
    assert(memcmp(buffer.bytes, expectedBytes.bytes, expectedBytes.length) == 0);
    assert(((const char *)buffer.bytes)[expectedBytes.length] == '\0');
    for (NSString *canary in canaries) {
        assert([expected rangeOfString:canary].location == NSNotFound);
    }
    // Emission uses the existing 1024-byte C buffer, unlike the size-query API.
    NSString *basic = [@"[Canaries] [ERROR] " stringByAppendingString:expected];
    NSString *structured = [@"[Canaries] [ERROR] [component=runtime] " stringByAppendingString:expected];
    NSData *basicBytes = [basic dataUsingEncoding:NSUTF8StringEncoding];
    NSData *structuredBytes = [structured dataUsingEncoding:NSUTF8StringEncoding];
    basic = [[NSString alloc] initWithData:[basicBytes subdataWithRange:NSMakeRange(0, MIN(basicBytes.length, FL_LOG_MAX_BUF - 1))]
                                 encoding:NSUTF8StringEncoding];
    structured = [[NSString alloc] initWithData:[structuredBytes subdataWithRange:NSMakeRange(0, MIN(structuredBytes.length, FL_LOG_MAX_BUF - 1))]
                                      encoding:NSUTF8StringEncoding];
    assert(basic && structured);
    FLLogCFields fields = {.component = "runtime"};
    unsigned verified = 0;
    calls = 0;
    FLLogCErrorH((FLLogCHandle)handle, input.UTF8String);
    expectEmission(basic, "%{public}s");
    verified++;
    calls = 0;
    FLLogOCErrorH(handle, input.UTF8String);
    expectEmission(basic, "%{public}s");
    verified++;
    for (int privacy = 0; privacy < 2; privacy++) {
        const char *route = privacy ? "%{public}s" : "%{private}s";
        calls = 0;
        FLLogCLogH((FLLogCHandle)handle, FL_LOG_LEVEL_ERROR, privacy, input.UTF8String);
        expectEmission(basic, route);
        verified++;
        calls = 0;
        FLLogOCLogH(handle, FLLogOCLevelError, privacy, input);
        expectEmission(basic, route);
        verified++;
        calls = 0;
        FLLogCLogStructuredH((FLLogCHandle)handle, FL_LOG_LEVEL_ERROR, privacy, &fields, input.UTF8String);
        expectEmission(structured, route);
        verified++;
        calls = 0;
        FLLogOCLogStructuredH(handle, FLLogOCLevelError, privacy, @"runtime", nil, nil, nil, input);
        expectEmission(structured, route);
        verified++;
    }
    calls = 0;
    FLLogCLogfH((FLLogCHandle)handle, FL_LOG_LEVEL_ERROR, "%s", input.UTF8String);
    if (strlen(input.UTF8String) < FL_LOG_MAX_BUF &&
        [@"[Canaries] [ERROR] " lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + expectedBytes.length < FL_LOG_MAX_BUF) {
        expectEmission(basic, "%{public}s");
        verified++;
    } else {
        assert(calls == 0);
    }
    return verified;
}

int main(int argc, const char *argv[]) {
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

        assert(argc == 2);
        NSData *fixtureData = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        assert(fixtureData);
        NSArray<NSDictionary *> *fixtures = [NSJSONSerialization JSONObjectWithData:fixtureData options:0 error:NULL];
        assert(fixtures.count > 0);
        handle = FLLogOCCreate(@"com.test.canaries", @"Canaries");
        assert(handle);
        for (NSDictionary *fixture in fixtures) {
            verified += verifyCanary(handle, fixture[@"input"], fixture[@"expected"], fixture[@"canaries"]);
        }
        NSString *lead = @"安全🙂 ready=";
        NSString *tail = @" token=CANARY-MAXIMUM";
        NSUInteger paddingLength = 65535 - [lead lengthOfBytesUsingEncoding:NSUTF8StringEncoding]
            - [tail lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        NSString *padding = [@"" stringByPaddingToLength:paddingLength withString:@"x" startingAtIndex:0];
        NSString *accepted = [[lead stringByAppendingString:padding] stringByAppendingString:tail];
        NSString *expected = [[lead stringByAppendingString:padding] stringByAppendingString:@" token=<redacted>"];
        assert([accepted lengthOfBytesUsingEncoding:NSUTF8StringEncoding] == 65535);
        verified += verifyCanary(handle, accepted, expected, @[@"CANARY-MAXIMUM"]);
        NSString *rejected = [accepted stringByAppendingString:@"x"];
        assert([rejected lengthOfBytesUsingEncoding:NSUTF8StringEncoding] == 65536);
        char rejectedBuffer[1] = {1};
        assert(FLLogCRedactMessage(rejected.UTF8String, rejectedBuffer, 1) == 0);
        assert(rejectedBuffer[0] == 0);
        FLLogCFields fields = {.component = "runtime"};
        calls = 0;
        FLLogCErrorH((FLLogCHandle)handle, rejected.UTF8String);
        FLLogCLogH((FLLogCHandle)handle, FL_LOG_LEVEL_ERROR, FL_LOG_PRIVACY_PRIVATE, rejected.UTF8String);
        FLLogCLogStructuredH((FLLogCHandle)handle, FL_LOG_LEVEL_ERROR, FL_LOG_PRIVACY_PRIVATE, &fields, rejected.UTF8String);
        FLLogOCErrorH(handle, rejected.UTF8String);
        FLLogOCLogH(handle, FLLogOCLevelError, FLLogOCPrivacyPrivate, rejected);
        FLLogOCLogStructuredH(handle, FLLogOCLevelError, FLLogOCPrivacyPrivate, @"runtime", nil, nil, nil, rejected);
        assert(calls == 0);
        FLLogOCDestroy(handle);
        printf("Objective-C actual adapter/C redactor: %u captured emissions verified\n", verified);
    }
    return 0;
}
