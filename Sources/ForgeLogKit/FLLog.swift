//
//  FLLog.swift
//  ForgeLogKit
//

import Foundation
import os.log

public struct FLLog {
    private let log: OSLog
    private let category: String

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
    private func prefix(_ level: StaticString) -> String {
        // [Default][INFO]
        return "[\(category)][\(level)] "
    }

    // MARK: - StaticString (near-zero cost)

    @inline(__always)
    public func info(_ msg: StaticString) {
        msg.withUTF8Buffer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            os_log("[%{public}@][INFO] %{public}s", log: log, type: .info,
                   category, baseAddress)
        }
    }

    @inline(__always)
    public func debug(_ msg: StaticString) {
        msg.withUTF8Buffer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            os_log("[%{public}@][DEBUG] %{public}s", log: log, type: .debug,
                   category, baseAddress)
        }
    }

    @inline(__always)
    public func warn(_ msg: StaticString) {
        msg.withUTF8Buffer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            os_log("[%{public}@][WARN] %{public}s", log: log, type: .default,
                   category, baseAddress)
        }
    }

    @inline(__always)
    public func error(_ msg: StaticString) {
        msg.withUTF8Buffer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            os_log("[%{public}@][ERROR] %{public}s", log: log, type: .error,
                   category, baseAddress)
        }
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
