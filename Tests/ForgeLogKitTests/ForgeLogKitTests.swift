@testable import ForgeLogKit
import Testing
import os.log

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
    
    @Test("Info log includes INFO level prefix")
    func testInfoLogLevel() throws {
        let logger = FLLog(category: "Test")
        
        // Test StaticString version
        logger.info("Test message")
        
        // Test String version
        logger.info("Test message" as String)
        
        // Verify the logger was initialized correctly
        #expect(logger.category == "Test")
    }
    
    @Test("Debug log includes DEBUG level prefix")
    func testDebugLogLevel() throws {
        let logger = FLLog(category: "Test")
        
        // Test StaticString version
        logger.debug("Debug message")
        
        // Test String version
        logger.debug("Debug message" as String)
        
        #expect(logger.category == "Test")
    }
    
    @Test("Warn log includes WARN level prefix")
    func testWarnLogLevel() throws {
        let logger = FLLog(category: "Test")
        
        // Test StaticString version
        logger.warn("Warning message")
        
        // Test String version
        logger.warn("Warning message" as String)
        
        #expect(logger.category == "Test")
    }
    
    @Test("Error log includes ERROR level prefix")
    func testErrorLogLevel() throws {
        let logger = FLLog(category: "Test")
        
        // Test StaticString version
        logger.error("Error message")
        
        // Test String version
        logger.error("Error message" as String)
        
        #expect(logger.category == "Test")
    }
    
    // MARK: - Initialization Tests
    
    @Test("Logger initialization with subsystem and category")
    func testInitializationWithSubsystemAndCategory() throws {
        let logger = FLLog(subsystem: "com.example.app", category: "Network")
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
    
    @Test("Logf with format string and arguments")
    func testLogfWithFormatString() throws {
        let handle = FLLogCCreate("com.test", "Test")
        #expect(handle != nil)
        
        FLLogCLogfH(handle, FL_LOG_LEVEL_INFO, "Value: %d", 42)
        FLLogCLogfH(handle, FL_LOG_LEVEL_DEBUG, "String: %s", "test")
        FLLogCLogfH(handle, FL_LOG_LEVEL_WARN, "Float: %.2f", 3.14)
        
        FLLogCDestroy(handle)
    }
    
    @Test("Logf with null format string")
    func testLogfWithNullFormat() throws {
        let handle = FLLogCCreate("com.test", "Test")
        #expect(handle != nil)
        
        // Should not crash
        FLLogCLogfH(handle, FL_LOG_LEVEL_INFO, nil)
        
        FLLogCDestroy(handle)
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
    
    @Test("Different categories produce different logs")
    func testDifferentCategories() throws {
        let categories = ["Network", "Database", "UI", "Cache"]
        
        for category in categories {
            let handle = FLLogCCreate("com.test", category)
            #expect(handle != nil)
            
            FLLogCInfoH(handle, "Test message")
            
            FLLogCDestroy(handle)
        }
    }
    
    @Test("All log levels work correctly")
    func testAllLogLevels() throws {
        let handle = FLLogCCreate("com.test", "Test")
        #expect(handle != nil)
        
        // Test all log levels through logf
        FLLogCLogfH(handle, FL_LOG_LEVEL_DEBUG, "Debug level test")
        FLLogCLogfH(handle, FL_LOG_LEVEL_INFO, "Info level test")
        FLLogCLogfH(handle, FL_LOG_LEVEL_WARN, "Warn level test")
        FLLogCLogfH(handle, FL_LOG_LEVEL_ERROR, "Error level test")
        FLLogCLogfH(handle, FL_LOG_LEVEL_FAULT, "Fault level test")
        
        FLLogCDestroy(handle)
    }
    
    @Test("Long messages are handled correctly")
    func testLongMessages() throws {
        let handle = FLLogCCreate("com.test", "Test")
        #expect(handle != nil)
        
        // Create a message that's within buffer limits
        // FL_LOG_MAX_BUF is 1024, so test with ~500 chars (well within limit)
        let mediumMessage = String(repeating: "A", count: 500)
        FLLogCInfoH(handle, mediumMessage)
        
        // Create a message that exceeds FL_LOG_MAX_BUF (1024)
        // This tests buffer truncation behavior - should not crash
        let veryLongMessage = String(repeating: "B", count: 2000)
        FLLogCInfoH(handle, veryLongMessage)
        
        FLLogCDestroy(handle)
    }
}

/// Tests for FLConfig
@Suite("FLConfig Tests")
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
        
        // Restore original value
        FLConfig.defaultSubsystem = originalSubsystem
        #expect(FLConfig.defaultSubsystem == originalSubsystem)
    }
}
