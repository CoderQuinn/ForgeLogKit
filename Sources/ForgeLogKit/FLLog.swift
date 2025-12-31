//
//  FLLog.swift
//  ForgeLogKit
//

import Foundation
import os.log

public struct FLLog {
    private let log: OSLog

    public init(
        subsystem: String? = nil,
        category: String? = nil
    ) {
        let sub = subsystem ?? FLConfig.defaultSubsystem
        let cat = category ?? "Default"
        log = OSLog(subsystem: sub, category: cat)
    }

    // MARK: - StaticString (zero-cost)

    @inline(__always)
    public func info(_ msg: StaticString) {
        os_log(msg, log: log, type: .info)
    }

    @inline(__always)
    public func debug(_ msg: StaticString) {
        os_log(msg, log: log, type: .debug)
    }

    @inline(__always)
    public func warn(_ msg: StaticString) {
        os_log(msg, log: log, type: .default)
    }

    @inline(__always)
    public func error(_ msg: StaticString) {
        os_log(msg, log: log, type: .error)
    }

    // MARK: - String (dynamic, explicit cost)

    @inline(__always)
    public func info(_ msg: String) {
        os_log("%{public}@", log: log, type: .info, msg)
    }

    @inline(__always)
    public func debug(_ msg: String) {
        os_log("%{public}@", log: log, type: .debug, msg)
    }

    @inline(__always)
    public func warn(_ msg: String) {
        os_log("%{public}@", log: log, type: .default, msg)
    }

    @inline(__always)
    public func error(_ msg: String) {
        os_log("%{public}@", log: log, type: .error, msg)
    }
}
