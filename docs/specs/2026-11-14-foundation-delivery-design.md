# ForgeLogKit foundation delivery

Status: implementation authorized on 2026-11-14 for this bounded foundation batch. Tracks [#11](https://github.com/CoderQuinn/ForgeLogKit/issues/11).

Baseline: main `1071bbdee0c921308f06d66ff18c71ebe68d7b26`; #14 lazy builders/redaction/lifetime fix already merged. Keep existing Swift/C/ObjC APIs, synchronous sink behavior and borrowed-handle contract. Do not introduce background queues or file sinks.

## Required behavior

Use shared synthetic canaries through the actual Swift/C/ObjC redaction/adaptor paths: multiline JSON private keys; quoted equals and whitespace boundaries; Unicode around secrets; embedded NUL behavior per each length-aware versus NUL-terminated API; exact accepted maximum input boundary and one-byte-over rejection. Inspect the current header to freeze numeric limits accurately before code. Assert emitted/redacted bytes contain no canary and useful safe context remains; a no-crash test is insufficient. Disabled message/fields builders must run zero times. Existing legal borrow/destroy-once tests remain authoritative; never exercise use-after-free as if supported.

Wire the real Objective-C capture harness into CI (it currently exists outside Scripts/ci.sh). If a canary demonstrates a bug, fix it minimally and retain RED evidence. Cover first-party Swift, C and ObjC production scope; report gaps explicitly rather than counting package Swift coverage as whole-library coverage.

Add a lightweight native benchmark harness for disabled builders, redaction sizes and 1/2/4/8 producers sharing a valid handle, with exact source/dirty/toolchain/executable/fixture provenance and raw samples. Synchronize handle lifetime across workers. Label batch averages accurately; no invented zero allocations or contention-free claims. Coordinate exclusive timing with controller.

Clean Git URL consumer proves the new main APIs/contracts and exact resolution; old 0.2.0 is documented as lagging. README retains no file/async backend boundary; rotation/export remain host responsibility. No release/tag. Rollback is previous sink/consumer lock and additive harness commit.


## Task 1 frozen byte canaries and API boundaries

The shared synthetic oracle is `Tests/ObjCRedactionHarness/canaries.json`.
Both Swift tests and the standalone Objective-C program read the same literal
input, expected UTF-8 output, and forbidden canaries. Existing alias, short
buffer, disabled-builder and legal borrow/destroy tests remain in place.

| Boundary | Frozen current behavior | Verification |
| --- | --- | --- |
| Multiline JSON private key and standalone PEM | Quoted JSON value becomes `<redacted>`; standalone PEM becomes `<redacted-private-key>`; surrounding safe Unicode/text remains | Shared `multiline-json-pem` and `standalone-pem` rows |
| Quoted `=` assignment | Normal, empty, escaped and unterminated values redact; a closed value preserves adjacent benign fields; an unclosed value consumes the remaining input | Four shared `quoted-equals*` rows |
| Unicode around and inside values | Preserve the exact UTF-8 bytes of safe context and remove the entire recognized secret value | Shared `unicode` row; compare bytes rather than only category or crash behavior |
| Embedded NUL in C message | Input ends at the first NUL; bytes after it are outside this API's message contract | Shared `nul-after-secret` and `nul-inside-secret` rows |
| Embedded NUL in Swift/NSString message | Both types can store NUL, but current `withCString` / `UTF8String` adapters pass a NUL-terminated message to C and therefore emit only the redacted prefix before it | The same two rows through actual adapters; no new length-bearing API |
| Redactor maximum input | Default `FL_LOG_MAX_INPUT_BYTES=65536` scans for NUL: 65,535 non-NUL UTF-8 bytes plus terminator are accepted; 65,536 are rejected with return zero and an empty writable output | A generated fixture with a multibyte safe prefix and secret tail at exactly 65,535 bytes, then one extra byte |
| Swift oversized message | Basic/legacy paths emit `<redacted-invalid-message>` with the normal prefix; structured paths emit nothing | Capture enabled Swift backend output |
| C/ObjC oversized message | Basic, explicit and structured emission produce no OS submission | Capture the actual compiled adapter/C OS submission boundary |
| C/ObjC accepted emission size | Size-query redactor/structured formatter returns the full redacted size. Existing emission uses `FL_LOG_MAX_BUF=1024`, so basic/structured submission is a maximum 1,023-byte prefix; printf rejects formatted input/output that does not fit | Exact accepted-boundary captured bytes and printf non-emission; no claim that truncation preserves arbitrary UTF-8 boundaries |
| Privacy/prefixes | Swift basic `[category][LEVEL] `; shared structured and C/ObjC basic `[category] [LEVEL] `. Legacy convenience APIs are public; explicit privacy is preserved | Exact bytes and public/private routes at capture boundaries |

The Swift capture seam replaces only its existing internal backend. The native
harness replaces only `os_log_with_type`; production Objective-C adapters, C
formatting/redaction and valid owned-handle lifecycle execute unchanged. These
checks prove submitted bytes and privacy format, not OS persistence. No
production defect was required to extend these characterization tests.

Coverage uses LLVM-instrumented source lines in all authored Swift/C/ObjC
production targets. The optional base argument to `Scripts/coverage.sh BASE`
also audits added lines owned by LLVM LCOV records in changed Swift/C/ObjC
production and test/harness files. It reports the numerator and denominator
and rejects missing coverage files. Shell orchestration and JSON/docs are
outside LLVM's language scope and have separate execution evidence. A zero
production-change denominator means no production executable lines changed;
it is not presented as a measured percentage.

## Task 2 frozen diagnostic interface

The exact CLI, schema 1 fields, independent fixture sizes and timing boundaries
are frozen in [the harness contract](../../Benchmarks/ForgeLogKit/README.md).
The standalone Release executable compiles unchanged production Swift/C
sources. Disabled Swift logging uses its existing internal backend seam;
shared-handle producers replace only C `os_log_with_type` with a thread-local
byte oracle. One owned handle exists per producer batch. Ready workers start
through a condition-variable gate; all workers complete and join before the
owner's single destroy call. The native guard rejects incomplete joins,
active borrowers and repeated destruction without executing an unsafe lifetime.

Run output records candidate/current SHA, dirty entries, toolchain and OS,
source manifest and executable/fixture hashes, raw batch nanoseconds and all
correctness/lifetime counters. Invalid provenance, oracle or lifetime evidence
produces no new result. Dirty runs are diagnostic only. `validate` requires
the recorded exact Git state and files, so inspect a historical result from
its recorded checkout. No production API, background work or persistent sink
is added. The controlled measurement includes capture comparisons/counting,
and producer scheduling/joins; it establishes neither OS persistence nor
allocator, tail-latency or application-workload performance.

Task 2 coverage accounts for every new Swift/C/Python/Bash executable file
with explicit whole-file and added-line counts, including test tooling.
Native LLVM summary lines and unique physical LCOV lines are distinguished;
Python and Bash require their own coverage records rather than an LLVM-only
claim. Task 1 production evidence remains separately frozen at its tested
revision; final combined-PR tooling coverage is an additional audit.
