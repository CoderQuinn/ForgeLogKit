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
- Swift, C, and Objective-C share one stable structured-field serialization
- Dynamic format strings are handled safely via buffering
- Swift, C, and Objective-C messages share one content-redaction pass before emission
- New unified logging calls default to private message data
- No dependency on app-level context or business logic
- Suitable for Network Extension (VPN) environments
- No file logging, no async pipeline, no backend abstraction (by design)

Hosts own persistence, rotation and export when those capabilities are needed.

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

let fields = FLLogFields(
  component: "packet-tunnel",
  phase: "connect",
  errorCode: "TCP_TIMEOUT",
  correlationID: "flow-42"
)!
log.log(.error, "connection failed", fields: fields)
```

The original `info(_:)`, `debug(_:)`, `warn(_:)`, and `error(_:)`
convenience methods keep their 0.2 public-message behavior for compatibility.
Their content is still redacted before emission. Use `log(_:_:privacy:)` or an
explicit privacy overload when the entire remaining message should also use
Unified Logging's private routing.

## Structured fields

For dynamic fields, use the additive lazy overload:

```swift
log.log(.debug, "connection status", lazyFields: {
  FLLogFields(component: "runtime", phase: "connect")
})
```

When the level is disabled, neither this closure nor the message is evaluated.
Otherwise fields are evaluated once, followed by the message once; returning nil
from the field builder drops the event without evaluating the message. Privacy
defaults to private, and output uses the same formatter/redactor as `fields:`.
Existing eager fields and public convenience overloads are unchanged. Identifier
validation is not anonymization: do not put domains, IP addresses, or secrets in fields.

Structured events use the same fixed field names and order from Swift, C, and
Objective-C:

```text
[network] [ERROR] [component=packet-tunnel][phase=connect][error_code=TCP_TIMEOUT][correlation_id=flow-42] connection failed
```

`component` is required; `phase`, `error_code`, and `correlation_id` are
optional and omitted when absent. Each supplied value must contain 1...64 ASCII
identifier bytes from letters, digits, `.`, `_`, `:`, or `-`. Inputs with
whitespace, delimiters, empty values, or longer identifiers fail closed rather
than creating ambiguous fields. These fields are product-independent
correlation identifiers, not a place for raw configuration or secrets. Message
content still passes through default redaction before emission.

## Default secret redaction

All Swift, C, and Objective-C entry points redact recognized secret-bearing
content before applying the requested public/private routing:

- case-insensitive named values such as `password`, `token`, `api_key`,
  `private_key`, and `proxy_url`, including query-string and quoted JSON forms
- complete `Authorization`, `Proxy-Authorization`, `Cookie`, `Set-Cookie`, and
  `X-API-Key` header values
- URL user information such as `socks5://user:password@proxy.example`
- `PrivateKey`, `PresharedKey`, and `HeaderProtectionKey` labels, including
  snake_case and hyphen-separated spellings, case-insensitively; complete name
  boundaries preserve benign lookalikes such as `PrivateKeyCount`
- complete PEM blocks whose label contains `PRIVATE KEY`

Values become `<redacted>` and private-key blocks become
`<redacted-private-key>`. The C redactor always NUL-terminates a supplied
non-empty buffer and computes truncation from already-redacted output, so a
short buffer cannot expose a partial matched value. Inputs that reach the 64
KiB scan bound fail closed: C/ObjC and Swift structured paths emit nothing;
Swift basic paths emit `<redacted-invalid-message>`. Privacy routing remains a separate
defense: callers should still avoid logging unlabeled raw secrets and should
use `.private` unless a message is intentionally public.
This is label-based defense in depth, not a configuration parser or a guarantee
of recognizing arbitrary secrets (including encoded/escaped field names).
Never pass raw keys to the logger. Unclosed quoted recognized values redact
through the end of input; quoted JSON and configuration assignments share the
same C redactor, including Swift lazy structured messages and Objective-C.

Local alias regressions: `swift test --filter testKeyAliasRedaction` checks
JSON/configuration values, escaped/unclosed quotes, case/name boundaries,
every short-buffer capacity, and Swift lazy/C structured output agreement.
`bash Scripts/test-objc-redaction.sh` compiles the actual ObjC adapter and C
implementation, captures only the OS submission boundary, and checks actual
submitted bytes and privacy routes across aliases, casing, multiline JSON,
escaped/unclosed quotes, benign lookalikes, and unquoted line boundaries. Each
sample also checks the C redactor's exact text and every truncated-buffer
capacity. Shared [byte canaries](Tests/ObjCRedactionHarness/canaries.json) additionally
cover Unicode, embedded NUL, multiline private keys and quoted assignments.
The exact 65,535-byte accepted / 65,536-byte rejected input boundary is checked
through Swift, C and Objective-C. Current Swift/NSString adapters pass
NUL-terminated C strings, so messages stop at their first embedded NUL. C/ObjC
submission uses the existing 1,024-byte buffer and may truncate accepted
messages to 1,023 bytes; size-query formatting returns the full required size.
These tests do not verify OS log persistence.

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
FLLogOCLogStructuredH(h, FLLogOCLevelError, FLLogOCPrivacyPrivate,
                     @"packet-tunnel", @"connect", @"TCP_TIMEOUT",
                     @"flow-42", @"connection failed");
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
FLLogCFields fields = {
    .component = "packet-tunnel",
    .phase = "connect",
    .errorCode = "TCP_TIMEOUT",
    .correlationID = "flow-42",
};
FLLogCLogStructuredH(h, FL_LOG_LEVEL_ERROR, FL_LOG_PRIVACY_PRIVATE,
                     &fields, "connection failed");
FLLogCDestroy(h);
```

C and Objective-C handles have one exclusive lifecycle owner. Logging and
`isEnabled` calls that borrowed the handle before registry removal may finish;
later racing calls fail closed. `FLLogCDestroy` / `FLLogOCDestroy` wait for
active borrows before reclaiming the handle. The owner must stop scheduling
new calls before destroy starts, invoke destroy exactly once, and never use the
handle value after destroy returns. This ownership rule avoids ambiguous
stale-handle reuse if an allocator later assigns the same address to a
different handle.

The three configuration APIs update the same process-wide value; call the one
owned by your process entry point. The configured default is used only when a
new logger or handle is created without an explicit subsystem. Existing
instances and explicit subsystem arguments are unchanged.

---

## Versioning

**Latest tagged version:** 0.2.0

The current main branch also contains structured fields, lazy field builders,
default redaction and the borrowed-handle lifetime contract. Those APIs are
absent from 0.2.0; pin an exact reviewed Git revision when consuming them.
This foundation work does not create a tag or release.

- Existing 0.2 convenience APIs retain their public-message behavior
- Recognized secret-bearing content is redacted before every entry point emits
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
checks complete Swift concurrency diagnostics, runs the actual Objective-C
capture harness, and enforces production coverage.

To run only the coverage gate:

```sh
./Scripts/coverage.sh
```

Coverage includes every instrumented file under `Sources/` in the Swift
`ForgeLogKit`, C `ForgeLogKitC`, and Objective-C `ForgeLogKitOC` targets. Test
and test-support sources are excluded. The total production line-coverage
threshold is 95%; the script writes a per-target and per-file summary to
`.build/coverage/production-summary.md`. The capture harness also emits a
separate instrumented LCOV file. To audit added LLVM-owned executable lines
in changed Swift/C/ObjC production and test/harness sources against an exact
base commit, run `./Scripts/coverage.sh BASE_SHA` (or set `COVERAGE_BASE=BASE_SHA`
when running `./Scripts/ci.sh`). The changed-line gate is
95% and records counts in `.build/coverage/changed-lines.json`; shell, JSON
and documentation are outside LLVM's instrumented language scope.

The Objective-C adapter and Apple Unified Logging APIs require a macOS/Xcode
host, so this first required gate intentionally uses one stable macOS runner
instead of a cross-platform matrix.

---

## Native diagnostic benchmark

The additive [standalone harness](Benchmarks/ForgeLogKit/README.md) checks
unevaluated disabled Swift builders, independent redaction byte oracles at
64/1024/16384/65535 bytes, and 1/2/4/8 producers sharing one owned C handle.
Every worker joins before the owner destroys that handle once.

```sh
bash Scripts/benchmark-logkit.sh check --output .build/logkit-check
# Coordinate an exclusive timing slot before running measurements:
bash Scripts/benchmark-logkit.sh run --output .build/logkit-run \
  --candidate "$(git rev-parse HEAD)" --timing-slot CONTROLLER_SLOT
bash Scripts/benchmark-logkit.sh validate .build/logkit-run/result.json
```

Release results retain exact Git/dirty/toolchain/OS provenance, source,
fixture and executable SHA-256 digests, correctness counters and every raw
batch sample. Qualification requires a clean exact revision; explicit
`--diagnostic` permits dirty input while retaining the diagnostic label.
The controlled capture seam does byte comparisons instead of OS submission;
measurements are batch averages including documented harness overhead.
The schema and measurement boundaries are frozen in the harness README.

---

## License

[Apache License 2.0](LICENSE)
