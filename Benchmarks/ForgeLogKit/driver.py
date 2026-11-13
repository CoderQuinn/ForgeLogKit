#!/usr/bin/env python3
"""Build, check and validate bounded native diagnostic measurements."""
import argparse
import datetime
import hashlib
import json
import math
import os
import pathlib
import platform
import re
import subprocess  # nosec B404 # Audited list argv below always disables the shell.
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = ROOT / "Benchmarks/ForgeLogKit"
FLAGS = {"swift": ["-O", "-whole-module-optimization", "-warnings-as-errors"], "c": ["-O3", "-std=c11"]}


def require(condition, message):
    if not condition:
        raise ValueError(message)

# Call sites fix trusted developer tools or the locally built binary; CLI paths/counts/SHA remain separate argv operands.
def command(args, *, env=None):
    return subprocess.run(args, cwd=ROOT, shell=False, check=True, text=True, capture_output=True, env=env).stdout.rstrip("\n")  # nosec B603 # Fixed tool/built-binary argv; values remain operands. # nosemgrep: python.lang.security.audit.dangerous-subprocess-use-audit.dangerous-subprocess-use-audit


def digest(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def canonical(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def source_manifest():
    files = [ROOT / "Package.swift", ROOT / "Scripts/benchmark-logkit.sh"]
    files += [p for folder in [ROOT / "Sources", HERE] for p in folder.rglob("*")
              if p.is_file() and "__pycache__" not in p.parts]
    return {str(p.relative_to(ROOT)): digest(p) for p in sorted(files)}


def git_state(candidate, diagnostic):
    actual = command(["git", "rev-parse", "HEAD"])
    require(re.fullmatch(r"[0-9a-f]{40}", candidate or "") is not None, "full candidate SHA required")
    require(candidate == actual, "candidate does not match HEAD")
    entries = command(["git", "status", "--porcelain=v1", "--untracked-files=all"]).splitlines()
    require(diagnostic or not entries, "dirty tree requires --diagnostic")
    return {"candidate": candidate, "actual": actual, "dirty": bool(entries), "dirty_entries": entries}


def build(output, coverage=False):
    output = pathlib.Path(output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    extra = ["-g", "-fprofile-instr-generate", "-fcoverage-mapping"] if coverage else []
    cflags = ["xcrun", "clang", *FLAGS["c"], *extra, "-Wall", "-Wextra", "-Werror",
              "-I", str(ROOT / "Sources/ForgeLogKitC"), "-I", str(HERE)]
    for source in ["FLLogC", "FLRedaction", "Native"]:
        path = HERE / "Native.c" if source == "Native" else ROOT / f"Sources/ForgeLogKitC/{source}.c"
        seam = ["-include", str(HERE / "Capture.h")] if source == "FLLogC" else []
        command([*cflags, *seam, "-c", str(path), "-o", str(output / f"{source}.o")])
    swiftflags = ["-g", "-profile-generate", "-profile-coverage-mapping"] if coverage else []
    binary = output / "benchmark"
    command(["xcrun", "swiftc", "-emit-executable", *FLAGS["swift"], *swiftflags, "-I", str(ROOT / "Sources/ForgeLogKitC"),
             "-I", str(HERE), "-module-name", "ForgeLogKitBenchmark",
             "-emit-module-path", str(output / "ForgeLogKitBenchmark.swiftmodule"),
             str(ROOT / "Sources/ForgeLogKit/Config.swift"),
             str(ROOT / "Sources/ForgeLogKit/FLLog.swift"), str(HERE / "main.swift"),
             *[str(output / f"{name}.o") for name in ["FLLogC", "FLRedaction", "Native"]], "-o", str(binary)])
    return binary


def validate_native(data, samples, iterations):
    checks = data["checks"]
    require(all(type(value) is int for value in checks.values()), "check counters must be integers")
    require(checks == {"message_builds": 0, "field_builds": 0, "gate_calls": samples * iterations * 2,
                       "literal_oracles": 3, "lifetime_guards": 4}, "disabled/oracle/lifetime checks invalid")
    rows = data["samples"]
    require(len(rows) == samples * 9, "missing native samples")
    seen = set()
    for row in rows:
        case, producers, size = row["case"], row["producers"], row["input_bytes"]
        require(all(type(row[key]) is int for key in ["sample", "producers", "input_bytes", "iterations_per_producer", "operations"]) and
                producers in [1, 2, 4, 8] and row["operations"] > 0, "integer/count metadata invalid")
        require(type(row["sample"]) is int and 0 <= row["sample"] < samples, "invalid sample index")
        key = (row["sample"], case, producers, size)
        require(key not in seen, "duplicate sample")
        seen.add(key)
        expected_iterations = iterations * 2 if case == "disabled_swift" else iterations
        require(row["iterations_per_producer"] == expected_iterations and
                row["operations"] == expected_iterations * producers, "operation count invalid")
        elapsed, average = row["elapsed_ns"], row["ns_per_operation"]
        require(type(elapsed) is int and elapsed > 0 and type(average) in [int, float] and
                math.isfinite(average) and math.isclose(average, elapsed / row["operations"], rel_tol=1e-12),
                "batch average invalid")
        if case == "disabled_swift":
            require(producers == 1 and size == 0, "disabled row invalid")
        elif case == "redact_c":
            require(producers == 1 and size in [64, 1024, 16384, 65535], "redaction row invalid")
        else:
            require(case == "shared_handle_c" and producers in [1, 2, 4, 8] and size == 48,
                    "producer row invalid")
            require(all(type(row[name]) is int for name in ["created", "completed", "joined", "submitted", "destroyed"]) and
                    all(row[name] == producers for name in ["created", "completed", "joined"]) and
                    row["submitted"] == iterations * producers and row["destroyed"] == 1,
                    "producer oracle/lifetime invalid")


def native(binary, fixture, samples, iterations, output):
    env = dict(os.environ, LLVM_PROFILE_FILE=str(pathlib.Path(output).resolve() / "native-%p.profraw"))
    data = json.loads(command([str(binary), str(fixture), str(samples), str(iterations)], env=env))
    validate_native(data, samples, iterations)
    return data


def validate_result(result):
    require(type(result["schema"]) is int and result["schema"] == 1 and result["kind"] in ["qualification", "diagnostic"], "schema invalid")
    provenance, configuration = result["provenance"], result["configuration"]
    require(re.fullmatch(r"[0-9a-f]{40}", provenance["candidate"]) is not None and
            provenance["candidate"] == provenance["actual"], "candidate provenance invalid")
    require(type(provenance["dirty"]) is bool and provenance["dirty"] == bool(provenance["dirty_entries"]) and
            (not provenance["dirty"] or result["kind"] == "diagnostic"), "dirty provenance invalid")
    require(all(isinstance(provenance[key], str) and provenance[key].strip()
                for key in ["swift", "clang", "xcode", "os", "timing_slot", "started_utc", "ended_utc"]), "missing provenance")
    require("Swift version" in provenance["swift"] and "clang version" in provenance["clang"] and
            "Xcode " in provenance["xcode"] and "ProductVersion:" in provenance["os"], "toolchain/OS provenance invalid")
    started, ended = [datetime.datetime.fromisoformat(provenance[key]) for key in ["started_utc", "ended_utc"]]
    require(started.tzinfo is not None and ended.tzinfo is not None and started <= ended, "timestamp provenance invalid")
    require(provenance["flags"] == FLAGS, "optimization provenance invalid")
    state = git_state(provenance["candidate"], result["kind"] == "diagnostic")
    require(all(state[key] == provenance[key] for key in state), "current Git provenance mismatch")
    require(provenance["source_manifest_sha256"] == canonical(provenance["sources"]), "source manifest invalid")
    require(set(provenance["sources"]) == set(source_manifest()), "source scope invalid")
    for path, sha in provenance["sources"].items():
        require(digest(ROOT / path) == sha, "source digest mismatch: " + path)
    for name in ["executable", "fixture"]:
        artifact = provenance[name]
        require(digest(artifact["path"]) == artifact["sha256"], name + " digest mismatch")
    count, iterations = configuration["samples"], configuration["iterations"]
    require(type(count) is int and type(iterations) is int and 1 <= count <= 100 and 1 <= iterations <= 1000000,
            "configuration invalid")
    validate_native(result, count, iterations)


def toolchain():
    return {"swift": command(["xcrun", "swiftc", "--version"]),
            "clang": command(["xcrun", "clang", "--version"]), "xcode": command(["xcodebuild", "-version"]),
            "os": platform.platform() + "\n" + command(["sw_vers"])}


def measure(args):
    destination = pathlib.Path(args.output).resolve() / "result.json"
    require(not destination.exists(), "result already exists; choose a new output directory")
    state = git_state(args.candidate, args.diagnostic)
    before = source_manifest()
    environment = toolchain()
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    binary = build(args.output)
    executable = {"path": str(binary), "sha256": digest(binary)}
    fixture = {"path": str(HERE / "fixtures.json"), "sha256": digest(HERE / "fixtures.json")}
    data = native(binary, fixture["path"], args.samples, args.iterations, args.output)
    require(source_manifest() == before and git_state(args.candidate, args.diagnostic) == state and toolchain() == environment,
            "source/toolchain changed during run")
    provenance = {**state, **environment, "flags": FLAGS,
                  "executable": executable, "fixture": fixture, "sources": before,
                  "source_manifest_sha256": canonical(before), "timing_slot": args.timing_slot,
                  "started_utc": started, "ended_utc": datetime.datetime.now(datetime.timezone.utc).isoformat()}
    result = {"schema": 1, "kind": "diagnostic" if args.diagnostic else "qualification",
              "provenance": provenance, "configuration": {"samples": args.samples, "iterations": args.iterations}, **data}
    validate_result(result)
    temporary = destination.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    temporary.replace(destination)
    print(destination)


def positive(value):
    number = int(value)
    if not 1 <= number <= 1000000:
        raise argparse.ArgumentTypeError("count must be in 1...1000000")
    return number


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    for name in ["build", "check", "run"]:
        sub = commands.add_parser(name)
        sub.add_argument("--output", required=True)
        if name != "run":
            sub.add_argument("--coverage", action="store_true")
        else:
            sub.add_argument("--candidate", required=True)
            sub.add_argument("--timing-slot", required=True)
            sub.add_argument("--diagnostic", action="store_true")
            sub.add_argument("--samples", type=positive, default=7)
            sub.add_argument("--iterations", type=positive, default=1000)
    commands.add_parser("validate").add_argument("result")
    args = parser.parse_args(argv)
    try:
        if args.action == "run":
            require(args.samples <= 100 and args.timing_slot.strip(), "invalid samples/timing slot")
            measure(args)
        elif args.action == "validate":
            validate_result(json.loads(pathlib.Path(args.result).read_text()))
            print("result validation passed")
        else:
            binary = build(args.output, args.coverage)
            if args.action == "check":
                data = native(binary, HERE / "fixtures.json", 1, 3, args.output)
                print("correctness checks passed: " + json.dumps(data["checks"], sort_keys=True))
            else:
                print(binary)
        return 0
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        detail = error.stderr if isinstance(error, subprocess.CalledProcessError) else str(error)
        print("benchmark failed: " + detail, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
