//
//  FLLog.swift
//  ForgeLogKit
//

import Foundation
import os.log

public struct FLLog {
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

    // MARK: - Prefix builder

    @inline(__always)
    internal func prefix(_ level: StaticString) -> String {
        // [Default][INFO]
        return "[\(category)][\(level)] "
    }

    // MARK: - StaticString (near-zero cost)

    @inline(__always)
    public func info(_ msg: StaticString) {
        os_log("%{public}@", log: log, type: .info,
               prefix("INFO") + String(describing: msg))
    }

    @inline(__always)
    public func debug(_ msg: StaticString) {
        os_log("%{public}@", log: log, type: .debug,
               prefix("DEBUG") + String(describing: msg))
    }

    @inline(__always)
    public func warn(_ msg: StaticString) {
        os_log("%{public}@", log: log, type: .default,
               prefix("WARN") + String(describing: msg))
    }

    @inline(__always)
    public func error(_ msg: StaticString) {
        os_log("%{public}@", log: log, type: .error,
               prefix("ERROR") + String(describing: msg))
    }

    // MARK: - String (dynamic)

    @inline(__always)
    public func info(_ msg: String) {
        os_log("%{public}@", log: log, type: .info,
               prefix("INFO") + msg)
    }

    @inline(__always)
    public func debug(_ msg: String) {
        os_log("%{public}@", log: log, type: .debug,
               prefix("DEBUG") + msg)
    }

    @inline(__always)
    public func warn(_ msg: String) {
        os_log("%{public}@", log: log, type: .default,
               prefix("WARN") + msg)
    }

    @inline(__always)
    public func error(_ msg: String) {
        os_log("%{public}@", log: log, type: .error,
               prefix("ERROR") + msg)
    }
}
