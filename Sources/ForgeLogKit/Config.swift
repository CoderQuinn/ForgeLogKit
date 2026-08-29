//
//  Config.swift
//  ForgeLogKit
//

import ForgeLogKitC

public enum FLConfig {
    private final class Storage: @unchecked Sendable {
        func readSubsystem() -> String {
            var capacity = FLLogCGetDefaultSubsystem(nil, 0)
            precondition(capacity > 0, "ForgeLogKit could not read the default subsystem")

            while true {
                var buffer = [CChar](repeating: 0, count: capacity)
                let requiredCapacity = buffer.withUnsafeMutableBufferPointer {
                    FLLogCGetDefaultSubsystem($0.baseAddress, $0.count)
                }
                precondition(requiredCapacity > 0, "ForgeLogKit could not read the default subsystem")

                if requiredCapacity <= buffer.count {
                    return buffer.withUnsafeBufferPointer {
                        String(cString: $0.baseAddress!)
                    }
                }

                capacity = requiredCapacity
            }
        }

        func writeSubsystem(_ value: String) {
            let didSet = value.withCString {
                FLLogCSetDefaultSubsystem($0) != 0
            }
            precondition(didSet, "ForgeLogKit could not store the default subsystem")
        }
    }

    private static let storage = Storage()

    /// The process-wide subsystem used when Swift, C, or Objective-C creates
    /// a logger without an explicit subsystem.
    ///
    /// Access is synchronized by the C core. Changes affect newly created
    /// loggers and handles; existing instances keep their original subsystem.
    public static var defaultSubsystem: String {
        get { storage.readSubsystem() }
        set { storage.writeSubsystem(newValue) }
    }
}
