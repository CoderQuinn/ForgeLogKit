# ForgeLogKit

[![CI / Tests](https://github.com/CoderQuinn/ForgeLogKit/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/CoderQuinn/ForgeLogKit/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2FCoderQuinn%2FForgeLogKit%2Fbadges%2Fcoverage.json)](https://github.com/CoderQuinn/ForgeLogKit/actions/workflows/ci.yml)
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
- Dynamic format strings are handled safely via buffering
- New unified logging calls default to private message data
- No dependency on app-level context or business logic
- Suitable for Network Extension (VPN) environments
- No file logging, no async pipeline, no backend abstraction (by design)

---

## Swift Usage

```swift
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
FLLogCHandle h = FLLogCCreate(NULL, "lwip");
FLLogCLogfH(h, FL_LOG_LEVEL_DEBUG, "recv len=%u", len);
FLLogCLogH(h, FL_LOG_LEVEL_INFO, FL_LOG_PRIVACY_PRIVATE,
           "user-selected path");
FLLogCDestroy(h);
```

---

## Versioning

**Latest tagged version:** 0.2.0

- Existing 0.2 convenience APIs retain their public-message behavior
- Internal behavior may evolve
- No API compatibility guarantee yet

---

## License

[Apache License 2.0](LICENSE)
