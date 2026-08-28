@testable import ForgeLogKit
import Foundation
import ForgeLogKitC
import ForgeLogKitCTestSupport
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

        #expect(logger.isEnabled(for: .debug) == false)
        #expect(probe.evaluationCount == 0)
        #expect(recorder.events.isEmpty)
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
        #expect(FLLogCTestRejectsInvalidLiteralInputs() == 1)
        #expect(FLLogCTestRejectsTinyFormattedBuffer() == 1)
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
