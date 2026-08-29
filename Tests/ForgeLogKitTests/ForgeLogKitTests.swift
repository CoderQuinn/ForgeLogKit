@testable import ForgeLogKit
import Foundation
import ForgeLogKitC
import ForgeLogKitCTestSupport
import ForgeLogKitOC
import Testing
import os.log

private struct RecordedLogEvent {
    let type: OSLogType
    let privacy: String
    let message: String
}

private final class LogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [RecordedLogEvent] = []

    func backend(isEnabled: Bool = true) -> FLLogBackend {
        FLLogBackend(
            isEnabled: { _ in isEnabled },
            emit: { [self] type, privacy, message in
                let privacyLabel: String
                switch privacy {
                case .private: privacyLabel = "private"
                case .public: privacyLabel = "public"
                }

                lock.lock()
                recordedEvents.append(
                    RecordedLogEvent(
                        type: type,
                        privacy: privacyLabel,
                        message: message
                    )
                )
                lock.unlock()
            }
        )
    }

    var events: [RecordedLogEvent] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEvents
    }
}

private final class MessageProbe {
    private(set) var evaluationCount = 0

    func evaluate() -> String {
        evaluationCount += 1
        return "evaluated"
    }
}

private final class UnexpectedValueRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [String] = []

    func record(_ value: String) {
        lock.lock()
        recordedValues.append(value)
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedValues
    }
}

private func readCDefaultSubsystem() -> String {
    var capacity = FLLogCGetDefaultSubsystem(nil, 0)
    #expect(capacity > 0)

    while capacity > 0 {
        var buffer = [CChar](repeating: 0, count: capacity)
        let requiredCapacity = buffer.withUnsafeMutableBufferPointer {
            FLLogCGetDefaultSubsystem($0.baseAddress, $0.count)
        }
        #expect(requiredCapacity > 0)
        if requiredCapacity <= buffer.count {
            return buffer.withUnsafeBufferPointer {
                String(cString: $0.baseAddress!)
            }
        }
        capacity = requiredCapacity
    }

    return ""
}

private func redactWithC(
    _ message: String,
    capacity requestedCapacity: Int? = nil
) -> (requiredCapacity: Int, output: String) {
    message.withCString { input in
        let requiredCapacity = FLLogCRedactMessage(input, nil, 0)
        let capacity = requestedCapacity ?? requiredCapacity
        var buffer = [CChar](repeating: 0, count: capacity)
        let returnedCapacity = buffer.withUnsafeMutableBufferPointer {
            FLLogCRedactMessage(input, $0.baseAddress, $0.count)
        }
        let output = buffer.isEmpty ? "" : buffer.withUnsafeBufferPointer {
            String(cString: $0.baseAddress!)
        }
        #expect(returnedCapacity == requiredCapacity)
        return (requiredCapacity, output)
    }
}

private func formatStructuredWithC(
    category: String?,
    level: ForgeLogKitC.FLLogLevel,
    fields: FLLogFields,
    message: String,
    capacity requestedCapacity: Int? = nil
) -> (requiredCapacity: Int, output: String) {
    func withCategory<Result>(
        _ body: (UnsafePointer<CChar>?) -> Result
    ) -> Result {
        guard let category else { return body(nil) }
        return category.withCString(body)
    }

    return fields.withCFields { fieldsPointer in
        withCategory { categoryPointer in
            message.withCString { messagePointer in
                let requiredCapacity = FLLogCFormatStructuredMessage(
                    categoryPointer,
                    level,
                    fieldsPointer,
                    messagePointer,
                    nil,
                    0
                )
                let capacity = requestedCapacity ?? requiredCapacity
                var buffer = [CChar](repeating: 0, count: capacity)
                let returnedCapacity = buffer.withUnsafeMutableBufferPointer {
                    FLLogCFormatStructuredMessage(
                        categoryPointer,
                        level,
                        fieldsPointer,
                        messagePointer,
                        $0.baseAddress,
                        $0.count
                    )
                }
                let output = buffer.isEmpty ? "" : buffer.withUnsafeBufferPointer {
                    String(cString: $0.baseAddress!)
                }
                #expect(returnedCapacity == requiredCapacity)
                return (requiredCapacity, output)
            }
        }
    }
}

private func containsCanary(_ text: String, canaries: [String]) -> Bool {
    canaries.contains { text.contains($0) }
}

/// Tests for FLLog Swift API to verify category and level prefixes
@Suite("FLLog Swift API Tests")
struct FLLogTests {
    
    // MARK: - Prefix Format Tests
    
    @Test("Prefix format includes category and level")
    func testPrefixFormat() throws {
        let logger = FLLog(subsystem: "com.test", category: "TestCategory")
        
        // Test that prefix method creates correct format
        // The prefix should be "[Category][LEVEL] "
        let infoPrefix = logger.prefix("INFO")
        #expect(infoPrefix == "[TestCategory][INFO] ")
        
        let debugPrefix = logger.prefix("DEBUG")
        #expect(debugPrefix == "[TestCategory][DEBUG] ")
        
        let warnPrefix = logger.prefix("WARN")
        #expect(warnPrefix == "[TestCategory][WARN] ")
        
        let errorPrefix = logger.prefix("ERROR")
        #expect(errorPrefix == "[TestCategory][ERROR] ")
    }
    
    @Test("Prefix format with default category")
    func testPrefixWithDefaultCategory() throws {
        let logger = FLLog()
        
        let prefix = logger.prefix("INFO")
        #expect(prefix == "[Default][INFO] ")
    }
    
    @Test("Prefix format with custom category")
    func testPrefixWithCustomCategory() throws {
        let categories = ["Network", "Database", "UI", "Analytics"]
        
        for category in categories {
            let logger = FLLog(category: category)
            let prefix = logger.prefix("INFO")
            #expect(prefix == "[\(category)][INFO] ")
        }
    }
    
    // MARK: - Log Level Tests
    
    @Test("Unified API maps every level and defaults messages to private")
    func testUnifiedLevelAndDefaultPrivacyRouting() {
        let recorder = LogRecorder()
        let logger = FLLog(category: "Routing", backend: recorder.backend())

        for level in FLLogLevel.allCases {
            logger.log(level, "message-\(level.rawValue)")
        }

        let events = recorder.events
        #expect(events.map(\.type.rawValue) == [
            OSLogType.debug.rawValue,
            OSLogType.info.rawValue,
            OSLogType.default.rawValue,
            OSLogType.error.rawValue,
            OSLogType.fault.rawValue,
        ])
        #expect(events.map(\.privacy) == Array(repeating: "private", count: 5))
        #expect(events.map(\.message) == [
            "[Routing][DEBUG] message-debug",
            "[Routing][INFO] message-info",
            "[Routing][WARN] message-warning",
            "[Routing][ERROR] message-error",
            "[Routing][FAULT] message-fault",
        ])
    }

    @Test("Explicit public and private routes are preserved")
    func testExplicitPrivacyRouting() {
        let recorder = LogRecorder()
        let logger = FLLog(category: "Privacy", backend: recorder.backend())

        logger.log(.info, "visible", privacy: .public)
        logger.error("secret", privacy: .private)

        #expect(recorder.events.map(\.privacy) == ["public", "private"])
        #expect(recorder.events.map(\.message) == [
            "[Privacy][INFO] visible",
            "[Privacy][ERROR] secret",
        ])
    }

    @Test("Structured fields validate identifiers and preserve stable order")
    func testStructuredFieldsAndFormatting() {
        let fields = FLLogFields(
            component: "packet-tunnel",
            phase: "connect",
            errorCode: "TCP_TIMEOUT",
            correlationID: "flow:42"
        )
        #expect(fields != nil)
        #expect(FLLogFields(component: "") == nil)
        #expect(FLLogFields(component: String(repeating: "x", count: 65)) == nil)
        #expect(FLLogFields(component: "packet tunnel") == nil)
        #expect(FLLogFields(component: "packet-tunnel", phase: "connect]") == nil)
        #expect(FLLogFields(component: "隧道") == nil)

        let recorder = LogRecorder()
        let logger = FLLog(category: "Routing", backend: recorder.backend())
        let canary = ["structured", "-secret"].joined()
        for level in FLLogLevel.allCases {
            logger.log(
                level,
                "token=\(canary)",
                fields: fields!,
                privacy: .public
            )
        }
        let longPrefix = String(repeating: "x", count: Int(FL_LOG_MAX_BUF) + 16)
        logger.log(
            .error,
            "\(longPrefix) token=\(canary)",
            fields: FLLogFields(component: "packet-tunnel")!
        )

        let events = recorder.events
        #expect(events.count == 6)
        #expect(events.dropLast().map(\.privacy) ==
            Array(repeating: "public", count: 5))
        #expect(events.dropLast().map(\.message) == [
            "[Routing] [DEBUG] [component=packet-tunnel][phase=connect]" +
                "[error_code=TCP_TIMEOUT][correlation_id=flow:42] token=<redacted>",
            "[Routing] [INFO] [component=packet-tunnel][phase=connect]" +
                "[error_code=TCP_TIMEOUT][correlation_id=flow:42] token=<redacted>",
            "[Routing] [WARN] [component=packet-tunnel][phase=connect]" +
                "[error_code=TCP_TIMEOUT][correlation_id=flow:42] token=<redacted>",
            "[Routing] [ERROR] [component=packet-tunnel][phase=connect]" +
                "[error_code=TCP_TIMEOUT][correlation_id=flow:42] token=<redacted>",
            "[Routing] [FAULT] [component=packet-tunnel][phase=connect]" +
                "[error_code=TCP_TIMEOUT][correlation_id=flow:42] token=<redacted>",
        ])
        #expect(events.last?.privacy == "private")
        #expect(events.last?.message ==
            "[Routing] [ERROR] [component=packet-tunnel] " +
                longPrefix + " token=<redacted>")
        #expect(events.allSatisfy { !$0.message.contains(canary) })
    }

    @Test("0.2 convenience overloads keep public routing")
    func testLegacyConvenienceRouting() {
        let recorder = LogRecorder()
        let logger = FLLog(category: "Compatibility", backend: recorder.backend())

        let staticDebug: StaticString = "static debug"
        let staticInfo: StaticString = "static info"
        let staticWarning: StaticString = "static warning"
        let staticError: StaticString = "static error"
        let staticFault: StaticString = "static fault"

        logger.debug(staticDebug)
        logger.debug("dynamic debug" as String)
        logger.info(staticInfo)
        logger.info("dynamic info" as String)
        logger.warn(staticWarning)
        logger.warn("dynamic warning" as String)
        logger.error(staticError)
        logger.error("dynamic error" as String)
        logger.fault(staticFault)
        logger.fault("dynamic fault" as String)

        let events = recorder.events
        #expect(events.map(\.privacy) == Array(repeating: "public", count: 10))
        #expect(events.map(\.type.rawValue) == [
            OSLogType.debug.rawValue, OSLogType.debug.rawValue,
            OSLogType.info.rawValue, OSLogType.info.rawValue,
            OSLogType.default.rawValue, OSLogType.default.rawValue,
            OSLogType.error.rawValue, OSLogType.error.rawValue,
            OSLogType.fault.rawValue, OSLogType.fault.rawValue,
        ])
        #expect(events.map(\.message) == [
            "[Compatibility][DEBUG] static debug",
            "[Compatibility][DEBUG] dynamic debug",
            "[Compatibility][INFO] static info",
            "[Compatibility][INFO] dynamic info",
            "[Compatibility][WARN] static warning",
            "[Compatibility][WARN] dynamic warning",
            "[Compatibility][ERROR] static error",
            "[Compatibility][ERROR] dynamic error",
            "[Compatibility][FAULT] static fault",
            "[Compatibility][FAULT] dynamic fault",
        ])
    }

    @Test("Privacy-aware convenience methods preserve level and privacy")
    func testPrivacyAwareConvenienceRouting() {
        let recorder = LogRecorder()
        let logger = FLLog(category: "PrivacyAPI", backend: recorder.backend())

        logger.debug("debug", privacy: .public)
        logger.info("info", privacy: .private)
        logger.warn("warn", privacy: .public)
        logger.error("error", privacy: .private)
        logger.fault("fault", privacy: .public)

        let events = recorder.events
        #expect(events.map(\.type.rawValue) == [
            OSLogType.debug.rawValue,
            OSLogType.info.rawValue,
            OSLogType.default.rawValue,
            OSLogType.error.rawValue,
            OSLogType.fault.rawValue,
        ])
        #expect(events.map(\.privacy) == [
            "public", "private", "public", "private", "public",
        ])
        #expect(events.map(\.message) == [
            "[PrivacyAPI][DEBUG] debug",
            "[PrivacyAPI][INFO] info",
            "[PrivacyAPI][WARN] warn",
            "[PrivacyAPI][ERROR] error",
            "[PrivacyAPI][FAULT] fault",
        ])
    }

    @Test("Unified logging backend accepts enabled, public, and private paths")
    func testUnifiedLoggingBackendSmoke() {
        let backend = FLLogBackend.unifiedLogging(
            OSLog(subsystem: "com.forgelogkit.tests", category: "Backend")
        )

        _ = backend.isEnabled(.info)
        backend.emit(.info, .public, "public smoke")
        backend.emit(.error, .private, "private smoke")
    }

    @Test("Disabled levels do not evaluate autoclosures")
    func testDisabledLevelIsLazy() {
        let recorder = LogRecorder()
        let logger = FLLog(
            category: "Disabled",
            backend: recorder.backend(isEnabled: false)
        )
        let probe = MessageProbe()

        logger.log(.debug, probe.evaluate())
        logger.info(probe.evaluate(), privacy: .private)
        logger.log(
            .error,
            probe.evaluate(),
            fields: FLLogFields(component: "runtime")!
        )

        #expect(logger.isEnabled(for: .debug) == false)
        #expect(probe.evaluationCount == 0)
        #expect(recorder.events.isEmpty)
    }

    @Test("Every Swift entry point redacts secret-bearing content before routing")
    func testSwiftEntryPointRedaction() {
        let canaries = [
            ["velvet", "-password"].joined(),
            ["amber", "-token"].joined(),
            ["bearer", "-credential"].joined(),
            ["proxy", "-user"].joined(),
            ["proxy", "-password"].joined(),
            ["key", "-material"].joined(),
            ["pem", "-payload"].joined(),
        ]
        let privateKeyBegin = ["-----BEGIN ", "PRIVATE KEY-----"].joined()
        let privateKeyEnd = ["-----END ", "PRIVATE KEY-----"].joined()
        let message = """
        password="\(canaries[0])" token=\(canaries[1])
        Authorization: Bearer \(canaries[2])
        endpoint=socks5://\(canaries[3]):\(canaries[4])@proxy.example:1080/path
        private_key=\(canaries[5])
        \(privateKeyBegin)
        \(canaries[6])
        \(privateKeyEnd)
        """
        let recorder = LogRecorder()
        let logger = FLLog(category: "Redaction", backend: recorder.backend())

        logger.info(message as String)
        logger.log(.error, message, privacy: .private)

        let events = recorder.events
        let leakDetected = events.contains {
            containsCanary($0.message, canaries: canaries)
        }
        let expectedMarkersPresent = events.allSatisfy {
            $0.message.contains("password=\"<redacted>\"") &&
                $0.message.contains("token=<redacted>") &&
                $0.message.contains("Authorization: <redacted>") &&
                $0.message.contains("socks5://<redacted>@proxy.example") &&
                $0.message.contains("private_key=<redacted>") &&
                $0.message.contains("<redacted-private-key>")
        }

        #expect(events.map(\.privacy) == ["public", "private"])
        #expect(leakDetected == false)
        #expect(expectedMarkersPresent)
    }

    @Test("Redactor covers aliases, JSON values, and sensitive headers")
    func testRedactionPatterns() {
        let tokenFields = [
            "password", "passwd", "pwd", "token", "access_token",
            "refresh_token", "api_key", "apikey", "secret", "private_key",
            "proxy_url",
        ]
        let lineFields = [
            "authorization", "proxy-authorization", "cookie", "set-cookie",
            "x-api-key",
        ]
        let canaries = (0 ..< tokenFields.count + lineFields.count).map {
            ["canary", "-\($0)", "-value"].joined()
        }
        let tokenLines = zip(tokenFields, canaries).enumerated().map { index, pair in
            index == 0
                ? "\"\(pair.0.uppercased())\": \"\(pair.1)\""
                : "\(pair.0)=\(pair.1)"
        }
        let lineLines = zip(lineFields, canaries.dropFirst(tokenFields.count)).map {
            "\($0.0): \($0.1) trailing metadata"
        }
        let result = redactWithC((tokenLines + lineLines).joined(separator: "\n"))
        let leakDetected = containsCanary(result.output, canaries: canaries)
        let markerCount = result.output.components(separatedBy: "<redacted>").count - 1

        #expect(result.requiredCapacity == result.output.utf8.count + 1)
        #expect(leakDetected == false)
        #expect(markerCount == canaries.count)
    }

    @Test("Redactor preserves benign lookalikes and public URLs")
    func testRedactionFalsePositiveBoundaries() {
        let benign = """
        tokenCount=7 passwordless=true secret handling enabled
        endpoint=https://proxy.example/path@segment?apikeyCount=2
        cookieJar=memory authorizationState=ready
        """

        #expect(redactWithC(benign).output == benign)
    }

    @Test("Redactor fails closed for bounded buffers and private-key tails")
    func testRedactionBoundaryBehavior() {
        let canaries = [
            ["tiny", "-secret"].joined(),
            ["url", "-user"].joined(),
            ["url", "-password"].joined(),
            ["unterminated", "-pem"].joined(),
        ]
        let privateKeyBegin = ["-----BEGIN OPENSSH ", "PRIVATE KEY-----"].joined()
        let tiny = redactWithC("token=\(canaries[0])", capacity: 8)
        let credentialURL = redactWithC(
            "http://\(canaries[1]):\(canaries[2])@proxy.example/path"
        )
        let privateKey = redactWithC("""
        \(privateKeyBegin)
        \(canaries[3])
        """)
        let empty = redactWithC("")
        let oversized = String(
            repeating: "X",
            count: 65_536
        )
        var oversizedBuffer = [CChar](repeating: 1, count: 1)
        let oversizedResult = oversized.withCString { input in
            oversizedBuffer.withUnsafeMutableBufferPointer {
                FLLogCRedactMessage(input, $0.baseAddress, $0.count)
            }
        }
        var nullBuffer = [CChar](repeating: 1, count: 1)
        let nullResult = nullBuffer.withUnsafeMutableBufferPointer {
            FLLogCRedactMessage(nil, $0.baseAddress, $0.count)
        }

        #expect(containsCanary(tiny.output, canaries: canaries) == false)
        #expect(tiny.requiredCapacity > tiny.output.utf8.count)
        #expect(containsCanary(credentialURL.output, canaries: canaries) == false)
        #expect(credentialURL.output == "http://<redacted>@proxy.example/path")
        #expect(containsCanary(privateKey.output, canaries: canaries) == false)
        #expect(privateKey.output == "<redacted-private-key>")
        #expect(empty.requiredCapacity == 1)
        #expect(empty.output.isEmpty)
        #expect(oversizedResult == 0)
        #expect(oversizedBuffer[0] == 0)
        #expect(nullResult == 0)
        #expect(nullBuffer[0] == 0)
    }
    
    // MARK: - Initialization Tests
    
    @Test("Logger initialization with subsystem and category")
    func testInitializationWithSubsystemAndCategory() throws {
        let logger = FLLog(subsystem: "com.example.app", category: "Network")
        #expect(logger.subsystem == "com.example.app")
        #expect(logger.category == "Network")
    }
    
    @Test("Logger initialization with default subsystem")
    func testInitializationWithDefaultSubsystem() throws {
        let logger = FLLog(category: "Test")
        #expect(logger.category == "Test")
    }
    
    @Test("Logger initialization with all defaults")
    func testInitializationWithDefaults() throws {
        let logger = FLLog()
        #expect(logger.category == "Default")
    }
    
    // MARK: - Message Format Tests
    
    @Test("Log message with StaticString")
    func testStaticStringMessage() throws {
        let logger = FLLog(category: "Test")
        
        // These should compile and run without issues
        logger.info("Static info message")
        logger.debug("Static debug message")
        logger.warn("Static warn message")
        logger.error("Static error message")
        
        #expect(logger.category == "Test")
    }
    
    @Test("Log message with dynamic String")
    func testDynamicStringMessage() throws {
        let logger = FLLog(category: "Test")
        let dynamicValue = "example"
        
        // These should compile and run without issues
        logger.info("Info at \(dynamicValue)")
        logger.debug("Debug at \(dynamicValue)")
        logger.warn("Warn at \(dynamicValue)")
        logger.error("Error at \(dynamicValue)")
        
        #expect(logger.category == "Test")
    }
    
    @Test("Log message with special characters")
    func testSpecialCharactersInMessage() throws {
        let logger = FLLog(category: "Test")
        
        // Test messages with special characters
        logger.info("Message with [brackets]")
        logger.info("Message with émojis 🚀")
        logger.info("Message with newline\ncharacter")
        
        #expect(logger.category == "Test")
    }
}

/// Tests for FLLogC C API to verify _emit function and formatting
@Suite("FLLogC C API Tests")
struct FLLogCTests {
    
    // MARK: - Handle Lifecycle Tests
    
    @Test("Create and destroy C log handle")
    func testHandleLifecycle() throws {
        let handle = FLLogCCreate("com.test", "TestCategory")
        #expect(handle != nil)
        
        FLLogCDestroy(handle)
        // Successfully destroyed, no crash
    }
    
    @Test("Create handle with null subsystem uses default")
    func testHandleWithNullSubsystem() throws {
        let handle = FLLogCCreate(nil, "TestCategory")
        #expect(handle != nil)
        
        FLLogCDestroy(handle)
    }
    
    @Test("Create handle with null category uses Default")
    func testHandleWithNullCategory() throws {
        let handle = FLLogCCreate("com.test", nil)
        #expect(handle != nil)
        
        FLLogCDestroy(handle)
    }
    
    @Test("Create handle with all null parameters")
    func testHandleWithAllNullParameters() throws {
        let handle = FLLogCCreate(nil, nil)
        #expect(handle != nil)
        
        FLLogCDestroy(handle)
    }
    
    // MARK: - Basic String API Tests
    
    @Test("Info log with handle")
    func testInfoLogWithHandle() throws {
        let handle = FLLogCCreate("com.test", "Test")
        #expect(handle != nil)
        
        FLLogCInfoH(handle, "Info message")
        
        FLLogCDestroy(handle)
    }
    
    @Test("Debug log with handle")
    func testDebugLogWithHandle() throws {
        let handle = FLLogCCreate("com.test", "Test")
        #expect(handle != nil)
        
        FLLogCDebugH(handle, "Debug message")
        
        FLLogCDestroy(handle)
    }
    
    @Test("Warn log with handle")
    func testWarnLogWithHandle() throws {
        let handle = FLLogCCreate("com.test", "Test")
        #expect(handle != nil)
        
        FLLogCWarnH(handle, "Warn message")
        
        FLLogCDestroy(handle)
    }
    
    @Test("Error log with handle")
    func testErrorLogWithHandle() throws {
        let handle = FLLogCCreate("com.test", "Test")
        #expect(handle != nil)
        
        FLLogCErrorH(handle, "Error message")
        
        FLLogCDestroy(handle)
    }
    
    @Test("Fault log with handle")
    func testFaultLogWithHandle() throws {
        let handle = FLLogCCreate("com.test", "Test")
        #expect(handle != nil)
        
        FLLogCFaultH(handle, "Fault message")
        
        FLLogCDestroy(handle)
    }
    
    // MARK: - Printf-style API Tests
    
    @Test("Variadic formatting preserves values, level, and privacy")
    func testLogfWithFormatString() {
        var event = FLLogCTestEvent()

        let result = FLLogCTestPrepareFormattedValues(
            "Formatting",
            FL_LOG_LEVEL_ERROR,
            FL_LOG_PRIVACY_PRIVATE,
            42,
            "worker",
            3.14159,
            &event
        )

        #expect(result == 1)
        #expect(FLLogCTestEventMessage(&event).map(String.init(cString:)) ==
            "[Formatting] [ERROR] count=42 name=worker ratio=3.14")
        #expect(FLLogCTestEventLogType(&event) == OSLogType.error.rawValue)
        #expect(FLLogCTestEventIsPublic(&event) == 0)
    }

    @Test("C structured formatter shares field order and redaction")
    func testCStructuredFormatting() {
        let fields = FLLogFields(
            component: "dns",
            phase: "upstream-query",
            errorCode: "TIMEOUT",
            correlationID: "request-7"
        )!
        let canary = ["c-structured", "-secret"].joined()
        let full = formatStructuredWithC(
            category: "Resolver",
            level: FL_LOG_LEVEL_ERROR,
            fields: fields,
            message: "password=\(canary)"
        )
        let minimal = formatStructuredWithC(
            category: nil,
            level: ForgeLogKitC.FLLogLevel(rawValue: 99),
            fields: FLLogFields(component: "dns")!,
            message: "failed"
        )
        let truncated = formatStructuredWithC(
            category: "Resolver",
            level: FL_LOG_LEVEL_ERROR,
            fields: fields,
            message: "password=\(canary)",
            capacity: 16
        )

        #expect(full.output ==
            "[Resolver] [ERROR] [component=dns][phase=upstream-query]" +
                "[error_code=TIMEOUT][correlation_id=request-7] password=<redacted>")
        #expect(!full.output.contains(canary))
        #expect(minimal.output == "[unknown] [UNKNOWN] [component=dns] failed")
        #expect(truncated.requiredCapacity == full.requiredCapacity)
        #expect(truncated.output == "[Resolver] [ERR")

        let handle = FLLogCCreate("com.test", "Structured")
        fields.withCFields { fieldsPointer in
            FLLogCLogStructuredH(
                handle,
                FL_LOG_LEVEL_ERROR,
                FL_LOG_PRIVACY_PRIVATE,
                fieldsPointer,
                "structured smoke"
            )
        }
        FLLogCDestroy(handle)
    }

    @Test("C structured formatter rejects malformed fields and messages")
    func testCStructuredFormattingBoundaries() {
        var buffer = [CChar](repeating: 1, count: 64)

        let nullFieldsResult = buffer.withUnsafeMutableBufferPointer {
            FLLogCFormatStructuredMessage(
                "Boundary",
                FL_LOG_LEVEL_INFO,
                nil,
                "message",
                $0.baseAddress,
                $0.count
            )
        }
        #expect(nullFieldsResult == 0)
        #expect(buffer[0] == 0)

        "bad component".withCString { invalidComponent in
            var fields = FLLogCFields(
                component: invalidComponent,
                phase: nil,
                errorCode: nil,
                correlationID: nil
            )
            buffer[0] = 1
            let result = buffer.withUnsafeMutableBufferPointer {
                FLLogCFormatStructuredMessage(
                    "Boundary",
                    FL_LOG_LEVEL_INFO,
                    &fields,
                    "message",
                    $0.baseAddress,
                    $0.count
                )
            }
            #expect(result == 0)
            #expect(buffer[0] == 0)
        }

        "dns".withCString { component in
            "".withCString { emptyPhase in
                var fields = FLLogCFields(
                    component: component,
                    phase: emptyPhase,
                    errorCode: nil,
                    correlationID: nil
                )
                buffer[0] = 1
                let result = buffer.withUnsafeMutableBufferPointer {
                    FLLogCFormatStructuredMessage(
                        "Boundary",
                        FL_LOG_LEVEL_INFO,
                        &fields,
                        "message",
                        $0.baseAddress,
                        $0.count
                    )
                }
                #expect(result == 0)
                #expect(buffer[0] == 0)
            }
        }

        let fields = FLLogFields(component: "dns")!
        fields.withCFields { fieldsPointer in
            buffer[0] = 1
            let nullMessageResult = buffer.withUnsafeMutableBufferPointer {
                FLLogCFormatStructuredMessage(
                    "Boundary",
                    FL_LOG_LEVEL_INFO,
                    fieldsPointer,
                    nil,
                    $0.baseAddress,
                    $0.count
                )
            }
            #expect(nullMessageResult == 0)
            #expect(buffer[0] == 0)
            #expect(FLLogCFormatStructuredMessage(
                "Boundary",
                FL_LOG_LEVEL_INFO,
                fieldsPointer,
                "message",
                nil,
                8
            ) > 0)
        }
    }

    @Test("C literal and formatted entry points redact canaries")
    func testCEntryPointRedaction() {
        let canaries = [
            ["c", "-password"].joined(),
            ["c", "-authorization"].joined(),
            ["c", "-url-user"].joined(),
            ["c", "-url-password"].joined(),
        ]
        var literalEvent = FLLogCTestEvent()
        var formattedEvent = FLLogCTestEvent()

        let literalResult = FLLogCTestPrepareLiteral(
            "Redaction",
            FL_LOG_LEVEL_ERROR,
            FL_LOG_PRIVACY_PUBLIC,
            "password=\(canaries[0])",
            &literalEvent
        )
        let credentialURL =
            "https://\(canaries[2]):\(canaries[3])@proxy.example:8443"
        let formattedResult = FLLogCTestPrepareSensitiveFormattedValues(
            canaries[1],
            credentialURL,
            &formattedEvent
        )
        let outputs = [literalEvent, formattedEvent].map { event in
            var copy = event
            return FLLogCTestEventMessage(&copy).map(String.init(cString:)) ?? ""
        }
        let leakDetected = outputs.contains {
            containsCanary($0, canaries: canaries)
        }
        let expectedMarkersPresent =
            outputs[0].contains("password=<redacted>") &&
            outputs[1].contains("Authorization: <redacted>") &&
            outputs[1].contains("https://<redacted>@proxy.example")

        #expect(literalResult == 1)
        #expect(formattedResult == 1)
        #expect(leakDetected == false)
        #expect(expectedMarkersPresent)
    }
    
    @Test("Null variadic format is rejected without an event")
    func testLogfWithNullFormat() {
        var event = FLLogCTestEvent()

        #expect(FLLogCTestPrepareNullFormat(&event) == 0)
        #expect(FLLogCTestEventMessage(&event).map(String.init(cString:)) == "")
    }

    @Test("C literal path maps every level and explicit privacy")
    func testPrivacyAwareCAPI() {
        let cases: [(
            ForgeLogKitC.FLLogLevel,
            ForgeLogKitC.FLLogPrivacy,
            UInt8,
            String,
            Int32
        )] = [
            (FL_LOG_LEVEL_DEBUG, FL_LOG_PRIVACY_PRIVATE,
             OSLogType.debug.rawValue, "DEBUG", 0),
            (FL_LOG_LEVEL_INFO, FL_LOG_PRIVACY_PUBLIC,
             OSLogType.info.rawValue, "INFO", 1),
            (FL_LOG_LEVEL_WARN, FL_LOG_PRIVACY_PRIVATE,
             OSLogType.default.rawValue, "WARN", 0),
            (FL_LOG_LEVEL_ERROR, FL_LOG_PRIVACY_PUBLIC,
             OSLogType.error.rawValue, "ERROR", 1),
            (FL_LOG_LEVEL_FAULT, FL_LOG_PRIVACY_PRIVATE,
             OSLogType.fault.rawValue, "FAULT", 0),
        ]

        for (level, privacy, expectedType, label, isPublic) in cases {
            var event = FLLogCTestEvent()
            #expect(FLLogCTestPrepareLiteral(
                "CPrivacy",
                level,
                privacy,
                "payload",
                &event
            ) == 1)
            #expect(FLLogCTestEventMessage(&event).map(String.init(cString:)) ==
                "[CPrivacy] [\(label)] payload")
            #expect(FLLogCTestEventLogType(&event) == expectedType)
            #expect(FLLogCTestEventIsPublic(&event) == isPublic)
        }
    }

    @Test("Unknown C levels and missing categories use safe fallbacks")
    func testUnknownLevelAndCategoryFallbacks() {
        var event = FLLogCTestEvent()
        let unknownLevel = ForgeLogKitC.FLLogLevel(rawValue: 99)
        let unknownPrivacy = ForgeLogKitC.FLLogPrivacy(rawValue: 99)

        #expect(FLLogCTestPrepareLiteral(
            nil,
            unknownLevel,
            unknownPrivacy,
            "payload",
            &event
        ) == 1)
        #expect(FLLogCTestEventMessage(&event).map(String.init(cString:)) ==
            "[unknown] [UNKNOWN] payload")
        #expect(FLLogCTestEventLogType(&event) == OSLogType.default.rawValue)
        #expect(FLLogCTestEventIsPublic(&event) == 0)
    }

    @Test("Explicit C logging covers enabled, privacy, formatting, and null formats")
    func testExplicitCLoggingPaths() {
        let handle = FLLogCCreate("com.test", "Explicit")
        #expect(handle != nil)

        _ = FLLogCIsEnabledH(handle, FL_LOG_LEVEL_INFO)
        FLLogCLogH(
            handle,
            FL_LOG_LEVEL_ERROR,
            FL_LOG_PRIVACY_PRIVATE,
            "private message"
        )
        FLLogCTestFormatted(handle)
        FLLogCTestPrivateFormatted(handle)
        FLLogCTestNullFormat(handle)

        FLLogCDestroy(handle)
    }

    @Test("C format helpers reject invalid inputs and insufficient prefix space")
    func testFormattingBoundaries() {
        var oversizedEvent = FLLogCTestEvent()
        let oversizedValue = String(repeating: "X", count: Int(FL_LOG_MAX_BUF))

        #expect(FLLogCTestRejectsInvalidLiteralInputs() == 1)
        #expect(FLLogCTestRejectsTinyFormattedBuffer() == 1)
        #expect(FLLogCTestPrepareOversizedFormattedValue(
            oversizedValue,
            &oversizedEvent
        ) == 0)
        #expect(FLLogCTestEventMessage(&oversizedEvent).map(String.init(cString:)) == "")
        #expect(FLLogCTestEventMessage(nil) == nil)
        #expect(FLLogCTestEventLogType(nil) == 0)
        #expect(FLLogCTestEventIsPublic(nil) == 0)
    }
    
    // MARK: - Edge Cases
    
    @Test("Log with null message")
    func testLogWithNullMessage() throws {
        let handle = FLLogCCreate("com.test", "Test")
        #expect(handle != nil)
        
        // Should not crash
        FLLogCInfoH(handle, nil)
        FLLogCDebugH(handle, nil)
        FLLogCWarnH(handle, nil)
        FLLogCErrorH(handle, nil)
        FLLogCFaultH(handle, nil)
        
        FLLogCDestroy(handle)
    }
    
    @Test("Destroy null handle")
    func testDestroyNullHandle() throws {
        // Should not crash
        FLLogCDestroy(nil)
    }
    
    @Test("Log with null handle")
    func testLogWithNullHandle() throws {
        // These should use OS_LOG_DEFAULT and not crash
        FLLogCInfoH(nil, "Message with null handle")
        FLLogCDebugH(nil, "Message with null handle")
        FLLogCWarnH(nil, "Message with null handle")
        FLLogCErrorH(nil, "Message with null handle")
        FLLogCFaultH(nil, "Message with null handle")
    }
    
    // MARK: - Category and Level Formatting Tests
    
    @Test("Different categories produce distinct formatted events")
    func testDifferentCategories() {
        let categories = ["Network", "Database", "UI", "Cache"]
        
        for category in categories {
            var event = FLLogCTestEvent()
            #expect(FLLogCTestPrepareLiteral(
                category,
                FL_LOG_LEVEL_INFO,
                FL_LOG_PRIVACY_PUBLIC,
                "Test message",
                &event
            ) == 1)
            #expect(FLLogCTestEventMessage(&event).map(String.init(cString:)) ==
                "[\(category)] [INFO] Test message")
        }
    }
    
    @Test("All log levels work correctly")
    func testAllLogLevels() throws {
        let handle = FLLogCCreate("com.test", "Test")
        #expect(handle != nil)
        
        FLLogCTestAllLevels(handle)
        
        FLLogCDestroy(handle)
    }
    
    @Test("Long C messages are terminated and truncated to the buffer")
    func testLongMessages() {
        let veryLongMessage = String(repeating: "B", count: 2000)
        var event = FLLogCTestEvent()

        #expect(FLLogCTestPrepareLiteral(
            "Bounds",
            FL_LOG_LEVEL_INFO,
            FL_LOG_PRIVACY_PUBLIC,
            veryLongMessage,
            &event
        ) == 1)

        let message = FLLogCTestEventMessage(&event).map(String.init(cString:))
        #expect(message?.count == Int(FL_LOG_MAX_BUF) - 1)
        #expect(message?.hasPrefix("[Bounds] [INFO] ") == true)
    }
}

/// Tests for FLConfig
@Suite("FLConfig Tests", .serialized)
struct FLConfigTests {
    
    @Test("Default subsystem is set correctly")
    func testDefaultSubsystem() throws {
        #expect(FLConfig.defaultSubsystem == "com.forgelogkit.default")
        #expect(readCDefaultSubsystem() == "com.forgelogkit.default")
        #expect(FLLogOCDefaultSubsystem() == "com.forgelogkit.default")
    }
    
    @Test("Default subsystem can be changed")
    func testChangeDefaultSubsystem() throws {
        let originalSubsystem = FLConfig.defaultSubsystem
        
        FLConfig.defaultSubsystem = "com.custom.subsystem"
        #expect(FLConfig.defaultSubsystem == "com.custom.subsystem")
        #expect(FLLog().subsystem == "com.custom.subsystem")
        #expect(FLLog(subsystem: "com.explicit.subsystem").subsystem ==
            "com.explicit.subsystem")
        
        // Restore original value
        FLConfig.defaultSubsystem = originalSubsystem
        #expect(FLConfig.defaultSubsystem == originalSubsystem)
    }

    @Test("Swift default subsystem is shared with C and Objective-C")
    func testSwiftDefaultSubsystemIsSharedAcrossLanguages() {
        let originalSubsystem = FLConfig.defaultSubsystem
        defer { FLConfig.defaultSubsystem = originalSubsystem }

        let expectedSubsystem = "com.forgelogkit.tests.swift"
        FLConfig.defaultSubsystem = expectedSubsystem

        #expect(FLLog(category: "SwiftContract").subsystem == expectedSubsystem)
        #expect(readCDefaultSubsystem() == expectedSubsystem)
        #expect(FLLogOCDefaultSubsystem() == expectedSubsystem)
    }

    @Test("C default subsystem is shared with Swift and Objective-C")
    func testCDefaultSubsystemIsSharedAcrossLanguages() {
        let originalSubsystem = FLConfig.defaultSubsystem
        defer { FLConfig.defaultSubsystem = originalSubsystem }

        let expectedSubsystem = "com.forgelogkit.tests.c"
        #expect(FLLogCSetDefaultSubsystem(expectedSubsystem) != 0)

        #expect(FLConfig.defaultSubsystem == expectedSubsystem)
        #expect(FLLogOCDefaultSubsystem() == expectedSubsystem)
        let handle = FLLogCCreate(nil, "CContract")
        #expect(handle != nil)
        FLLogCDestroy(handle)
    }

    @Test("Objective-C default subsystem is shared with Swift and C")
    func testObjectiveCDefaultSubsystemIsSharedAcrossLanguages() {
        let originalSubsystem = FLConfig.defaultSubsystem
        defer { FLConfig.defaultSubsystem = originalSubsystem }

        let expectedSubsystem = "com.forgelogkit.tests.objc"
        #expect(FLLogOCSetDefaultSubsystem(expectedSubsystem))

        #expect(FLConfig.defaultSubsystem == expectedSubsystem)
        #expect(readCDefaultSubsystem() == expectedSubsystem)
        let handle = FLLogOCCreate(nil, "ObjectiveCContract")
        FLLogOCDestroy(handle)
    }

    @Test("Concurrent FLConfig reads and writes remain atomic")
    func testConcurrentDefaultSubsystemAccess() {
        let originalSubsystem = FLConfig.defaultSubsystem
        defer { FLConfig.defaultSubsystem = originalSubsystem }

        let candidateValues = (0..<16).map {
            "com.forgelogkit.concurrent.\($0)-" + String(repeating: "x", count: $0)
        }
        let validValues = Set(candidateValues + [originalSubsystem])
        let unexpectedValues = UnexpectedValueRecorder()

        DispatchQueue.concurrentPerform(iterations: 2_000) { index in
            FLConfig.defaultSubsystem = candidateValues[index % candidateValues.count]
            let observedValue = FLConfig.defaultSubsystem
            if !validValues.contains(observedValue) {
                unexpectedValues.record(observedValue)
            }
        }

        FLConfig.defaultSubsystem = "com.forgelogkit.concurrent.final"
        #expect(unexpectedValues.values.isEmpty)
        #expect(FLConfig.defaultSubsystem == "com.forgelogkit.concurrent.final")
    }
}
