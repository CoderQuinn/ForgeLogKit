# Native diagnostic benchmark contract (schema 1)

This standalone harness compiles the unchanged Swift and C sources with `-O`
and `-O3`. It is not a SwiftPM product or a new logging backend.

```
bash Scripts/benchmark-logkit.sh build --output DIR [--coverage]
bash Scripts/benchmark-logkit.sh check --output DIR [--coverage]
bash Scripts/benchmark-logkit.sh run --output DIR --candidate FULL_SHA --timing-slot LABEL [--diagnostic] [--samples N] [--iterations N]
bash Scripts/benchmark-logkit.sh validate RESULT_JSON
```

`build` only compiles. `check` builds and runs one untimed correctness batch
with three operations per case; its nanoseconds are discarded. `--coverage`
instruments the check binary and writes LLVM raw profiles. `run` requires the
controller's exclusive timing slot label, an exact current HEAD SHA, 1...100
samples (default 7) and 1...1000000 iterations per producer (default 1000).
A clean source tree is required unless `--diagnostic` is explicit. Dirty
results are always diagnostic. Missing, mismatched or changed provenance,
oracle failures, incomplete producer joins or non-single destruction fail
closed with a nonzero exit and no result JSON. Exit 2 is invalid CLI usage;
exit 1 is a build, validation, correctness or provenance failure. Existing
`result.json` output is never overwritten; select a new output directory.

Schema 1 is one JSON object: `schema`, `kind` (`qualification` or
`diagnostic`), `provenance`, `configuration`, `checks`, and `samples`.
`provenance` records candidate and actual Git SHA, dirty status/entries,
Swift/Clang/Xcode versions, OS information, optimization flags, executable path and
SHA-256, fixture path and SHA-256, every source path and SHA-256, canonical
source-manifest SHA-256, timing-slot label and UTC start/end timestamps.
`configuration` records sample count and iterations. `checks` records zero
message/field builder invocations, literal redaction oracle cases and four
producer lifetime guards. `samples` retains every native batch's case,
producer count, input size, per-producer iterations, total operations,
elapsed nanoseconds and arithmetic nanoseconds per operation. Producer rows
also retain created/completed/joined worker counts, submitted calls and
exactly one handle destruction after joins. `validate` rechecks this schema,
all row invariants, the current exact Git state and on-disk source/binary/fixture digests; it does not
retime or make an OS-persistence assertion.

The disabled Swift case uses the existing internal backend seam with a false
level gate and a counted gate closure; its timing includes that counter.
Both lazy message and lazy field builders must remain unevaluated. Redaction
cases use independent literal canaries plus generated 64, 1024, 16384 and
65535-byte inputs whose expected safe prefix and `<redacted>` replacement
are constructed independently of the redactor. Each timed batch reuses an
allocated output buffer and includes C redaction calls and return checks;
size query/allocation and final byte-oracle comparison are outside timing.

The 1/2/4/8-producer case creates one owned C handle per batch, starts pthread
workers through a condition-variable gate, borrows that shared handle using
the real `FLLogCLogH`, joins every worker, then calls destroy exactly once.
Timing starts before releasing the ready workers and ends after all joins;
it includes scheduling/join cost. A thread-local nonpersistent capture seam
replaces only `os_log_with_type`, compares every submitted byte and privacy
format to the independent oracle, and counts submissions. It adds comparison
and counting cost. It does not measure OS submission, persistence, allocations,
p99 latency, zero-copy behavior or an application workload. Values are batch
averages for this controlled harness only; no cross-machine claim is implied.

## Focused correctness and coverage

Run `python3 -m unittest discover -s Benchmarks/ForgeLogKit -p 'test_*.py'`.
The writer/drift test reports `not_run` (unittest skip) unless
`FORGELOGKIT_TIMING_SLOT` is set to the controller-granted exclusive slot.
Do not set it without that coordination. A correctness check's internal clock
readings are discarded, and an instrumented binary is never a timing artifact.

Native line coverage comes from `check --coverage` and the instrumented Python
test runs: merge `.build/benchmark-tests-coverage/*.profraw` using
`xcrun llvm-profdata merge -sparse`, then export with `xcrun llvm-cov` against
that directory's `benchmark`. Measure both `main.swift` and `Native.c` plus the
capture-header macro expansion. Python's driver and tests are measured with
coverage.py; Bash wrapper lines are measured independently with kcov. Report
all authored executable languages, whole-file and exact added-line counts,
with a 95% gate; the package's existing LLVM gate alone does not cover this
tooling. JSON/headers without LLVM executable records and prose add no
executable-line denominator. Retain the raw reports and disclose any gap.
