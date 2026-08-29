# ForgeLogKit

<p align="center">
  <strong>English</strong> |
  <a href="README.zh-CN.md">简体中文</a>
</p>

[![CI / Tests](https://github.com/CoderQuinn/ForgeLogKit/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/CoderQuinn/ForgeLogKit/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/CoderQuinn/ForgeLogKit)](LICENSE)

ForgeLogKit is a lightweight logging infrastructure built on top of `os_log`,
designed for use across **Swift, Objective-C, and pure C** code.

It is intended for low-level components such as networking stacks, VPN /
Network Extension, and mixed-language projects.

---

## Installation (Swift Package Manager)

Add the package:

```swift
dependencies: [
  .package(url: "https://github.com/CoderQuinn/ForgeLogKit.git", .upToNextMinor(from: "0.2.0")),
],
```

## Components

ForgeLogKit is split into three layers:

- **ForgeLogKitC**
  - Pure C wrapper around `os_log`
  - Safe handling for dynamic `printf`-style formats
  - Explicit public/private privacy controls
  - Suitable for lwIP / C / performance-critical paths

- **ForgeLogKitOC**
  - Objective-C adapter over the C layer
  - Convenience APIs for ObjC codebases

- **ForgeLogKit**
  - Swift wrapper for `os_log`
  - Unified level and privacy APIs
  - Concurrency-safe configuration and `Sendable` logger values
  - Source-compatible `StaticString` and `String` convenience APIs

---

## Design Notes

- All logging ultimately goes through **`os_log`**
- Swift, C, and Objective-C share one process-wide default subsystem
- Dynamic format strings are handled safely via buffering
- New unified logging calls default to private message data
- No dependency on app-level context or business logic
- Suitable for Network Extension (VPN) environments
- No file logging, no async pipeline, no backend abstraction (by design)

---

## Swift Usage

```swift
// Configure once during process startup. C and Objective-C handles created
// with a nil subsystem use the same value.
FLConfig.defaultSubsystem = "com.example.product.network-extension"

let log = FLLog(category: "network")
let path = "/Users/example/Documents"

log.info("connected")
log.debug("state updated")
log.error("connection failed")
log.fault("unrecoverable state")
// StaticString and String convenience overloads remain available.

// The unified API lazily evaluates messages and defaults to private data.
log.log(.info, "selected path: \(path)")
log.log(.error, "cleanup failed", privacy: .public)

// Privacy-aware convenience overloads are also available.
log.info("user-selected path: \(path)", privacy: .private)
```

The original `info(_:)`, `debug(_:)`, `warn(_:)`, and `error(_:)`
convenience methods keep their 0.2 public-message behavior for compatibility.
Use `log(_:_:privacy:)` or an explicit privacy overload for sensitive data.

---

## Objective-C Usage

```objc
// Use this when Objective-C owns process startup configuration.
FLLogOCSetDefaultSubsystem(@"com.example.product.network-extension");

FLLogOCHandle h = FLLogOCCreate(nil, @"network");
FLLogOCInfoH(h, "connected");
FLLogOCErrorH(h, "connection failed");
FLLogOCLogH(h, FLLogOCLevelInfo, FLLogOCPrivacyPrivate,
            @"user-selected path");
FLLogOCDestroy(h);
```

---

## C Usage

```c
/* Use this when C owns process startup configuration. */
FLLogCSetDefaultSubsystem("com.example.product.network-extension");

FLLogCHandle h = FLLogCCreate(NULL, "lwip");
FLLogCLogfH(h, FL_LOG_LEVEL_DEBUG, "recv len=%u", len);
FLLogCLogH(h, FL_LOG_LEVEL_INFO, FL_LOG_PRIVACY_PRIVATE,
           "user-selected path");
FLLogCDestroy(h);
```

The three configuration APIs update the same process-wide value; call the one
owned by your process entry point. The configured default is used only when a
new logger or handle is created without an explicit subsystem. Existing
instances and explicit subsystem arguments are unchanged.

---

## Versioning

**Latest tagged version:** 0.2.0

- Existing 0.2 convenience APIs retain their public-message behavior
- Internal behavior may evolve
- No API compatibility guarantee yet

---

## Development and CI

Run the same macOS gate used by GitHub Actions from the repository root:

```sh
./Scripts/ci.sh
```

The gate resets and resolves package dependencies, prints the active Swift,
Xcode, and macOS toolchains, builds and tests Debug and Release configurations,
checks complete Swift concurrency diagnostics, and enforces production coverage.

To run only the coverage gate:

```sh
./Scripts/coverage.sh
```

Coverage includes every instrumented file under `Sources/` in the Swift
`ForgeLogKit`, C `ForgeLogKitC`, and Objective-C `ForgeLogKitOC` targets. Test
and test-support sources are excluded. The total production line-coverage
threshold is 95%; the script writes a per-target and per-file summary to
`.build/coverage/production-summary.md`.

The Objective-C adapter and Apple Unified Logging APIs require a macOS/Xcode
host, so this first required gate intentionally uses one stable macOS runner
instead of a cross-platform matrix.

---

## License

[Apache License 2.0](LICENSE)
