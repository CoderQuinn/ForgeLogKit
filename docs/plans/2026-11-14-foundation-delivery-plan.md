# ForgeLogKit foundation implementation plan

> Use superpowers:subagent-driven-development. Begin only after coordinator confirms G0 review complete.

**Goal:** deliver this bounded foundation increment with reproducible evidence.
**Architecture:** preserve current production contracts; add verification/tooling and narrowly reproduced fixes.
**Tech Stack:** existing repository toolchain.
**Spec:** [Design](../specs/2026-11-14-foundation-delivery-design.md).

## Global constraints

- Preserve existing public API and original dirty workspaces; work only in the assigned isolated checkout.
- No unrelated dependencies, business routing decisions or host features. Only synthetic fixtures and public repository facts may be committed.
- First-party production and changed executable lines each >=95%; report numerator/denominator and authored C/ObjC/Swift/Go scope explicitly. Do not hide a shortfall with exclusions.
- Unknown/blocked/not_run is not passed. Record exact base..head, toolchain, commands and consumer pins.
- Implementation: GPT-6.1 SOL xhigh. Independent spec and quality review: Astra high. No merge, bypass, tags or release.
- Same-machine performance runs are serialized by the coordinator; building/testing may run concurrently, timing claims must wait for exclusive access.

## Review Focus

- Evidence generated from a different revision or dirty input being presented as qualified.
- Error handling that changes existing outputs or leaks borrowed memory/secrets.
- Duplicate tests that miss actual API/adaptor boundaries.
- Coverage exclusions concealing authored code and inherited changes being credited as new.
- Missing build/reader/performance capability being labeled passed.

### Task 1: Cross-language canary delivery

**Files:** `Tests/ForgeLogKitTests/`, `Tests/ObjCRedactionHarness/`, `Scripts/ci.sh`, `Scripts/test-objc-redaction.sh`, `Scripts/coverage.sh` as needed, README. Production redaction only for reproduced failures.
**Interfaces:** existing Swift lazy logging, C redaction/handle and ObjC adapter; additive tests and consumer proof. Benchmark scope belongs to Task 2.

- [ ] Freeze canary/API boundary table in spec; inspect current tests to avoid duplicating #14.
- [ ] RED: missing actual ObjC CI invocation and any newly uncovered canary boundary. Preserve failing reproduction before minimal fix.
- [ ] Add deterministic canaries across actual adapters and wire harness to CI; extend coverage accounting to authored languages where missing.
- [ ] GREEN: Debug/Release, strict concurrency, coverage, actual ObjC harness, clean Git consumer exact revision, changed-line audit. Record both production numerator/denominator and gaps.
- [ ] Commit and report base..head/evidence/rollback for independent review before Task 2.

### Task 2: Native diagnostic benchmark with bounded lifetime

**Files:** new `Benchmarks/ForgeLogKit/` harness and `Scripts/benchmark-logkit.sh`, focused harness checks, README/spec provenance documentation. No new production backend or public API.
**Interfaces:** existing redaction and valid owned C handle; additive benchmark command/result schema.

- [ ] Freeze exact CLI and result schema. Validate disabled builders execute zero times, redaction output matches synthetic canaries, and 1/2/4/8 producer runs join before destroy-once.
- [ ] Add native Release measurements with candidate SHA/dirty/toolchain/OS/executable/fixture digests and raw samples. Use a controlled nonpersistent capture seam; describe its measurement boundary accurately.
- [ ] RED→GREEN for invalid/missing provenance, oracle failure and lifetime synchronization. Dirty runs are diagnostic, never qualification. No invented allocation/zero-copy/p99 claims.
- [ ] Run harness correctness checks, relevant existing regression gates and clean consumer compatibility as needed by the diff. Request exclusive timing slot; commit and report for independent review.

