//
//  Config.swift
//  ForgeLogKit
//

import Foundation

public enum FLConfig {
    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var subsystem = "com.forgelogkit.default"

        func readSubsystem() -> String {
            lock.lock()
            defer { lock.unlock() }
            return subsystem
        }

        func writeSubsystem(_ value: String) {
            lock.lock()
            defer { lock.unlock() }
            subsystem = value
        }
    }

    private static let storage = Storage()

    /// The subsystem used when ``FLLog`` is initialized without one.
    ///
    /// Access is synchronized so configuration remains safe when loggers are
    /// created from multiple concurrency domains.
    public static var defaultSubsystem: String {
        get { storage.readSubsystem() }
        set { storage.writeSubsystem(newValue) }
    }
}
