//
//  FLLog.swift
//  ForgeLogKit
//

import Foundation
import ForgeLogKitC
import os.log

public enum FLLogLevel: String, CaseIterable, Sendable {
    case debug
    case info
    case warning
    case error
    case fault

    internal var label: StaticString {
        switch self {
        case .debug: "DEBUG"
        case .info: "INFO"
        case .warning: "WARN"
        case .error: "ERROR"
        case .fault: "FAULT"
        }
    }

    internal var osLogType: OSLogType {
        switch self {
        case .debug: .debug
        case .info: .info
        case .warning: .default
        case .error: .error
        case .fault: .fault
        }
    }

    internal var cLevel: ForgeLogKitC.FLLogLevel {
        switch self {
        case .debug: FL_LOG_LEVEL_DEBUG
        case .info: FL_LOG_LEVEL_INFO
        case .warning: FL_LOG_LEVEL_WARN
        case .error: FL_LOG_LEVEL_ERROR
        case .fault: FL_LOG_LEVEL_FAULT
        }
    }
}

public enum FLLogPrivacy: Sendable {
    case `private`
    case `public`
}

/// Validated, product-independent fields for correlating one structured event.
///
/// `component` is required. The remaining fields are optional. Each supplied
/// value must contain 1...64 ASCII identifier bytes from `A-Z`, `a-z`, `0-9`,
/// `.`, `_`, `:`, or `-`. The restricted alphabet keeps the shared Swift, C,
/// and Objective-C serialization unambiguous.
public struct FLLogFields: Hashable, Sendable {
    public let component: String
    public let phase: String?
    public let errorCode: String?
    public let correlationID: String?

    public init?(
        component: String,
        phase: String? = nil,
        errorCode: String? = nil,
        correlationID: String? = nil
    ) {
        guard Self.isValid(component),
              phase.map(Self.isValid) ?? true,
              errorCode.map(Self.isValid) ?? true,
              correlationID.map(Self.isValid) ?? true else {
            return nil
        }

        self.component = component
        self.phase = phase
        self.errorCode = errorCode
        self.correlationID = correlationID
    }

    private static func isValid(_ value: String) -> Bool {
        guard (1 ... 64).contains(value.utf8.count) else { return false }
        return value.utf8.allSatisfy { byte in
            (byte >= 65 && byte <= 90) ||
                (byte >= 97 && byte <= 122) ||
                (byte >= 48 && byte <= 57) ||
                byte == 46 || byte == 95 || byte == 58 || byte == 45
        }
    }

    internal func withCFields<Result>(
        _ body: (UnsafePointer<FLLogCFields>) -> Result
    ) -> Result {
        component.withCString { componentPointer in
            withOptionalCString(phase) { phasePointer in
                withOptionalCString(errorCode) { errorCodePointer in
                    withOptionalCString(correlationID) { correlationIDPointer in
                        var fields = FLLogCFields(
                            component: componentPointer,
                            phase: phasePointer,
                            errorCode: errorCodePointer,
                            correlationID: correlationIDPointer
                        )
                        return withUnsafePointer(to: &fields, body)
                    }
                }
            }
        }
    }

    private func withOptionalCString<Result>(
        _ value: String?,
        _ body: (UnsafePointer<CChar>?) -> Result
    ) -> Result {
        guard let value else { return body(nil) }
        return value.withCString(body)
    }
}

/// Internal indirection that keeps Unified Logging observable in unit tests
/// without exposing a production hook as public API.
internal struct FLLogBackend: @unchecked Sendable {
    let isEnabled: (OSLogType) -> Bool
    let emit: (OSLogType, FLLogPrivacy, String) -> Void

    static func unifiedLogging(_ log: OSLog) -> Self {
        Self(
            isEnabled: { log.isEnabled(type: $0) },
            emit: { type, privacy, message in
                switch privacy {
                case .private:
                    os_log(
                        "%{private}@",
                        log: log,
                        type: type,
                        message
                    )
                case .public:
                    os_log(
                        "%{public}@",
                        log: log,
                        type: type,
                        message
                    )
                }
            }
        )
    }
}

internal enum FLLogRedactor {
    private static let failureMarker = "<redacted-invalid-message>"

    static func redact(_ message: String) -> String {
        message.withCString { input in
            let requiredCapacity = FLLogCRedactMessage(input, nil, 0)
            guard requiredCapacity > 0 else { return failureMarker }

            var buffer = [CChar](repeating: 0, count: requiredCapacity)
            let writtenCapacity = buffer.withUnsafeMutableBufferPointer {
                FLLogCRedactMessage(input, $0.baseAddress, $0.count)
            }
            guard writtenCapacity == requiredCapacity else { return failureMarker }
            return buffer.withUnsafeBufferPointer {
                String(cString: $0.baseAddress!)
            }
        }
    }
}

/// A lightweight, concurrency-safe wrapper around Unified Logging.
public struct FLLog: Sendable {
    private let backend: FLLogBackend
    internal let subsystem: String
    internal let category: String

    public init(
        subsystem: String? = nil,
        category: String? = nil
    ) {
        let sub = subsystem ?? FLConfig.defaultSubsystem
        let cat = category ?? "Default"
        self.subsystem = sub
        self.category = cat
        backend = .unifiedLogging(OSLog(subsystem: sub, category: cat))
    }

    internal init(
        subsystem: String = "com.forgelogkit.tests",
        category: String,
        backend: FLLogBackend
    ) {
        self.subsystem = subsystem
        self.category = category
        self.backend = backend
    }

    // MARK: - Unified API

    /// Returns whether Unified Logging currently enables the requested level.
    @inline(__always)
    public func isEnabled(for level: FLLogLevel) -> Bool {
        backend.isEnabled(level.osLogType)
    }

    /// Logs a lazily evaluated message. New call sites default to private data.
    @inline(__always)
    public func log(
        _ level: FLLogLevel,
        _ message: @autoclosure () -> String,
        privacy: FLLogPrivacy = .private
    ) {
        guard isEnabled(for: level) else { return }
        emit(level, message(), privacy: privacy)
    }

    /// Logs one structured event using the shared Swift/C/Objective-C field
    /// contract. The message remains lazy and defaults to private routing.
    @inline(__always)
    public func log(
        _ level: FLLogLevel,
        _ message: @autoclosure () -> String,
        fields: FLLogFields,
        privacy: FLLogPrivacy = .private
    ) {
        guard isEnabled(for: level) else { return }
        emit(level, message(), fields: fields, privacy: privacy)
    }

    // MARK: - Prefix builder

    @inline(__always)
    internal func prefix(_ level: StaticString) -> String {
        "[\(category)][\(level)] "
    }

    @inline(__always)
    private func prefix(_ level: FLLogLevel) -> String {
        prefix(level.label)
    }

    // MARK: - Existing public convenience API

    // These overloads preserve the 0.2 behavior where convenience messages
    // are public. Privacy-sensitive call sites should use log(_:_:privacy:)
    // or the explicit privacy overloads below.

    @inline(__always)
    public func info(_ message: StaticString) {
        emit(.info, String(describing: message), privacy: .public)
    }

    @inline(__always)
    public func debug(_ message: StaticString) {
        emit(.debug, String(describing: message), privacy: .public)
    }

    @inline(__always)
    public func warn(_ message: StaticString) {
        emit(.warning, String(describing: message), privacy: .public)
    }

    @inline(__always)
    public func error(_ message: StaticString) {
        emit(.error, String(describing: message), privacy: .public)
    }

    @inline(__always)
    public func fault(_ message: StaticString) {
        emit(.fault, String(describing: message), privacy: .public)
    }

    @inline(__always)
    public func info(_ message: String) {
        emit(.info, message, privacy: .public)
    }

    @inline(__always)
    public func debug(_ message: String) {
        emit(.debug, message, privacy: .public)
    }

    @inline(__always)
    public func warn(_ message: String) {
        emit(.warning, message, privacy: .public)
    }

    @inline(__always)
    public func error(_ message: String) {
        emit(.error, message, privacy: .public)
    }

    @inline(__always)
    public func fault(_ message: String) {
        emit(.fault, message, privacy: .public)
    }

    // MARK: - Privacy-aware convenience API

    @inline(__always)
    public func info(
        _ message: @autoclosure () -> String,
        privacy: FLLogPrivacy
    ) {
        log(.info, message(), privacy: privacy)
    }

    @inline(__always)
    public func debug(
        _ message: @autoclosure () -> String,
        privacy: FLLogPrivacy
    ) {
        log(.debug, message(), privacy: privacy)
    }

    @inline(__always)
    public func warn(
        _ message: @autoclosure () -> String,
        privacy: FLLogPrivacy
    ) {
        log(.warning, message(), privacy: privacy)
    }

    @inline(__always)
    public func error(
        _ message: @autoclosure () -> String,
        privacy: FLLogPrivacy
    ) {
        log(.error, message(), privacy: privacy)
    }

    @inline(__always)
    public func fault(
        _ message: @autoclosure () -> String,
        privacy: FLLogPrivacy
    ) {
        log(.fault, message(), privacy: privacy)
    }

    // MARK: - Emission

    @inline(__always)
    private func emit(
        _ level: FLLogLevel,
        _ message: String,
        privacy: FLLogPrivacy
    ) {
        let formattedMessage = prefix(level) + FLLogRedactor.redact(message)
        backend.emit(level.osLogType, privacy, formattedMessage)
    }

    @inline(__always)
    private func emit(
        _ level: FLLogLevel,
        _ message: String,
        fields: FLLogFields,
        privacy: FLLogPrivacy
    ) {
        guard let formattedMessage = fields.withCFields({ fieldsPointer in
            category.withCString { categoryPointer in
                message.withCString { messagePointer -> String? in
                    let requiredCapacity = FLLogCFormatStructuredMessage(
                        categoryPointer,
                        level.cLevel,
                        fieldsPointer,
                        messagePointer,
                        nil,
                        0
                    )
                    guard requiredCapacity > 0 else { return nil }

                    var buffer = [CChar](
                        repeating: 0,
                        count: requiredCapacity
                    )
                    let returnedCapacity = buffer.withUnsafeMutableBufferPointer {
                        FLLogCFormatStructuredMessage(
                            categoryPointer,
                            level.cLevel,
                            fieldsPointer,
                            messagePointer,
                            $0.baseAddress,
                            $0.count
                        )
                    }
                    guard returnedCapacity == requiredCapacity else { return nil }
                    return buffer.withUnsafeBufferPointer {
                        String(cString: $0.baseAddress!)
                    }
                }
            }
        }) else { return }

        backend.emit(level.osLogType, privacy, formattedMessage)
    }
}
