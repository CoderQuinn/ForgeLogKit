# ForgeLogKit

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
  - Suitable for lwIP / C / performance-critical paths

- **ForgeLogKitOC**
  - Objective-C adapter over the C layer
  - Convenience APIs for ObjC codebases

- **ForgeLogKit**
  - Swift wrapper for `os_log`
  - Simple, explicit APIs
  - Optimized paths for `StaticString`

---

## Design Notes

- All logging ultimately goes through **`os_log`**
- Dynamic format strings are handled safely via buffering
- No dependency on app-level context or business logic
- Suitable for Network Extension (VPN) environments
- No file logging, no async pipeline, no backend abstraction (by design)

---

## Swift Usage

```swift
let log = FLLog(category: "network")

log.info("connected")
log.debug("state updated")
log.error("connection failed")
// StaticString variants are zero-cost; String variants have explicit cost.

---

## Objective-C Usage

```objc
FLLogOCHandle h = FLLogOCCreate(nil, @"network");
FLLogOCInfoH(h, "connected");
FLLogOCErrorH(h, "connection failed");
```

---

## C Usage

```c
FLLogCHandle h = FLLogCCreate(NULL, "lwip");
FLLogCLogfH(h, FL_LOG_LEVEL_DEBUG, "recv len=%u", len);
```

---

## Versioning

**Current version:** 0.2.0

- APIs are usable and stable for intended use cases
- Internal behavior may evolve
- No API compatibility guarantee yet

---

## License

Apache License 2.0
