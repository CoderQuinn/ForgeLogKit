//
//  FLLog.swift
//  ForgeLogKit
//

import Foundation
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
}

public enum FLLogPrivacy: Sendable {
    case `private`
    case `public`
}

/// A lightweight, concurrency-safe wrapper around Unified Logging.
public struct FLLog: Sendable {
    private let log: OSLog
    internal let category: String

    public init(
        subsystem: String? = nil,
        category: String? = nil
    ) {
        let sub = subsystem ?? FLConfig.defaultSubsystem
        let cat = category ?? "Default"
        self.category = cat
        log = OSLog(subsystem: sub, category: cat)
    }

    // MARK: - Unified API

    /// Returns whether Unified Logging currently enables the requested level.
    @inline(__always)
    public func isEnabled(for level: FLLogLevel) -> Bool {
        log.isEnabled(type: level.osLogType)
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
        let formattedMessage = prefix(level) + message
        switch privacy {
        case .private:
            os_log(
                "%{private}@",
                log: log,
                type: level.osLogType,
                formattedMessage
            )
        case .public:
            os_log(
                "%{public}@",
                log: log,
                type: level.osLogType,
                formattedMessage
            )
        }
    }
}
