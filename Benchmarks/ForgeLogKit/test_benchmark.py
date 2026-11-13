"""Behavior checks: leaks, skipped joins, stale provenance and bad samples must fail."""
import contextlib
import copy
import importlib.util
import io
import json
import os
import pathlib
import subprocess  # nosec B404 # Literal Bash fixture below runs without a shell.
import tempfile
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("benchmark_driver", ROOT / "Benchmarks/ForgeLogKit/driver.py")
driver = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(driver)


class NativeContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.output = ROOT / ".build/benchmark-tests-coverage"
        cls.binary = driver.build(cls.output, coverage=True)
        cls.data = driver.native(cls.binary, driver.HERE / "fixtures.json", 1, 3, cls.output)

    def cli(self, *args, expected=0):
        out, error = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(error):
            code = driver.main(list(args))
        self.assertEqual(code, expected, error.getvalue())
        return out.getvalue(), error.getvalue()

    def test_correctness_command_checks_disabled_oracle_and_joined_lifetime(self):
        result = subprocess.run(  # nosec B603 # Fully literal local Bash/check argv below; shell=False.
            ["bash", "Scripts/benchmark-logkit.sh", "check", "--output", ".build/benchmark-test"],
            cwd=ROOT, shell=False, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, "native check command required: " + result.stderr)
        self.assertIn("correctness checks passed", result.stdout)
        self.assertEqual(self.data["checks"]["message_builds"], 0)
        self.assertEqual(self.data["checks"]["field_builds"], 0)
        for row in self.data["samples"]:
            if row["case"] == "shared_handle_c":
                self.assertEqual((row["joined"], row["completed"], row["destroyed"]),
                                 (row["producers"], row["producers"], 1))

    def test_build_and_coverage_check_cli(self):
        out, _ = self.cli("build", "--output", str(self.output))
        self.assertIn("benchmark", out)
        out, _ = self.cli("check", "--output", str(self.output), "--coverage")
        self.assertIn("correctness checks passed", out)
        self.assertTrue(list(self.output.glob("native-*.profraw")))

    def test_native_rejects_wrong_oracles_without_emitting_result(self):
        fixture = json.loads((driver.HERE / "fixtures.json").read_text())
        for field in ["canaries", "sizeExpectedTail", "producerExpected", "sizes"]:
            changed = copy.deepcopy(fixture)
            if field == "canaries":
                changed[field][0]["expected"] = "LEAKED-CANARY"
            elif field == "sizes":
                changed[field] = [64]
            else:
                changed[field] = "WRONG-ORACLE"
            with self.subTest(field=field), tempfile.TemporaryDirectory() as temporary:
                path = pathlib.Path(temporary) / "fixture.json"
                path.write_text(json.dumps(changed))
                with self.assertRaises(subprocess.CalledProcessError) as failure:
                    driver.native(self.binary, path, 1, 3, self.output)
                self.assertEqual(failure.exception.stdout, "")
                self.assertIn("oracle" if field != "sizes" else "shape", failure.exception.stderr)

    def test_native_rejects_missing_and_invalid_counts(self):
        for args in [[], ["fixture", "bad", "3"], ["fixture", "0", "3"]]:
            with self.subTest(args=args), self.assertRaises(subprocess.CalledProcessError):
                driver.command([str(self.binary), *args], env=dict(os.environ, LLVM_PROFILE_FILE=str(self.output / "invalid-%p.profraw")))

    def test_native_validator_rejects_skipped_joins_and_duplicate_samples(self):
        mutations = [
            ("checks", "message_builds", 1), ("checks", "message_builds", False), ("checks", "field_builds", 1),
            ("row", "joined", 0), ("row", "completed", 0), ("row", "destroyed", 2),
            ("row", "submitted", 0), ("row", "operations", 0),
            ("row", "elapsed_ns", 0), ("row", "producers", 0), ("row", "producers", True), ("row", "ns_per_operation", float("nan")),
            ("row", "sample", 2), ("row", "input_bytes", 49),
            ("row", "case", "other"), ("row", "producers", 3),
        ]
        for scope, key, value in mutations:
            changed = copy.deepcopy(self.data)
            target = changed["checks"] if scope == "checks" else changed["samples"][-1]
            target[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                driver.validate_native(changed, 1, 3)
        for transform in [lambda rows: rows.pop(), lambda rows: rows.__setitem__(1, rows[0])]:
            changed = copy.deepcopy(self.data)
            transform(changed["samples"])
            with self.assertRaises(ValueError):
                driver.validate_native(changed, 1, 3)
        for index, key, value in [(0, "input_bytes", 1), (1, "input_bytes", 65), (1, "producers", 2)]:
            changed = copy.deepcopy(self.data)
            changed["samples"][index][key] = value
            with self.assertRaises(ValueError):
                driver.validate_native(changed, 1, 3)

    def test_bad_candidate_and_dirty_inputs_fail_before_build(self):
        sha = driver.command(["git", "rev-parse", "HEAD"])
        for candidate in ["", "main", "f" * 40]:
            with self.subTest(candidate=candidate), self.assertRaises(ValueError):
                driver.git_state(candidate, True)
        with mock.patch.object(driver, "command", side_effect=[sha, " M example.swift"]):
            with self.assertRaisesRegex(ValueError, "dirty tree"):
                driver.git_state(sha, False)
        self.cli("run", "--output", str(self.output), "--candidate", "bad", "--timing-slot", "test", expected=1)
        self.cli("run", "--output", str(self.output), "--candidate", sha, "--timing-slot", " ", expected=1)
        self.cli("run", "--output", str(self.output), "--candidate", sha, "--timing-slot", "test", "--samples", "101", expected=1)
        self.assertFalse((self.output / "result.json").exists())

    def result(self):
        sha = driver.command(["git", "rev-parse", "HEAD"])
        state = driver.git_state(sha, True)
        sources = driver.source_manifest()
        # This fixture validates the reader; it is never emitted as a timing result.
        provenance = {**state, "sources": sources, "source_manifest_sha256": driver.canonical(sources),
                      "flags": driver.FLAGS, "swift": "Apple Swift version 6 reader fixture", "clang": "Apple clang version 21 reader fixture",
                      "xcode": "Xcode 26 reader fixture",
                      "os": "ProductVersion: reader fixture", "timing_slot": "reader-only", "started_utc": "2026-11-14T01:00:00+00:00",
                      "ended_utc": "2026-11-14T01:01:00+00:00", "executable": {"path": str(self.binary), "sha256": driver.digest(self.binary)},
                      "fixture": {"path": str(driver.HERE / "fixtures.json"), "sha256": driver.digest(driver.HERE / "fixtures.json")}}
        return {"schema": 1, "kind": "diagnostic", "provenance": provenance,
                "configuration": {"samples": 1, "iterations": 3}, **copy.deepcopy(self.data)}

    def test_result_reader_requires_complete_actual_provenance_and_digests(self):
        result = self.result()
        driver.validate_result(result)
        mutations = [("root", "schema", 2), ("root", "kind", "other"),
                     ("provenance", "candidate", "f" * 40), ("provenance", "swift", ""),
                     ("provenance", "flags", {}), ("provenance", "clang", "unknown"),
                     ("provenance", "started_utc", "2026-11-14T01:02:00+00:00"), ("provenance", "source_manifest_sha256", "0" * 64),
                     ("provenance", "dirty", "false"), ("configuration", "samples", 0),
                     ("configuration", "iterations", False)]
        for scope, key, value in mutations:
            changed = copy.deepcopy(result)
            (changed if scope == "root" else changed[scope])[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                driver.validate_result(changed)
        for key in ["candidate", "os", "executable", "sources"]:
            changed = copy.deepcopy(result)
            del changed["provenance"][key]
            with self.subTest(missing=key), self.assertRaises(KeyError):
                driver.validate_result(changed)
        for name in ["executable", "fixture"]:
            changed = copy.deepcopy(result)
            changed["provenance"][name]["sha256"] = "0" * 64
            with self.subTest(digest=name), self.assertRaisesRegex(ValueError, "digest mismatch"):
                driver.validate_result(changed)
        changed = copy.deepcopy(result)
        source = next(iter(changed["provenance"]["sources"]))
        changed["provenance"]["sources"][source] = "0" * 64
        changed["provenance"]["source_manifest_sha256"] = driver.canonical(changed["provenance"]["sources"])
        with self.assertRaisesRegex(ValueError, "source digest"):
            driver.validate_result(changed)
        del changed["provenance"]["sources"][source]
        changed["provenance"]["source_manifest_sha256"] = driver.canonical(changed["provenance"]["sources"])
        with self.assertRaisesRegex(ValueError, "scope"):
            driver.validate_result(changed)
        changed = copy.deepcopy(result)
        changed["provenance"]["dirty_entries"] = [" M invented"]
        changed["provenance"]["dirty"] = True
        with self.assertRaisesRegex(ValueError, "Git provenance"):
            driver.validate_result(changed)
        with tempfile.TemporaryDirectory() as temporary:
            path = pathlib.Path(temporary) / "reader.json"
            path.write_text(json.dumps(result))
            out, _ = self.cli("validate", str(path))
            self.assertIn("validation passed", out)
            path.write_text("{}")
            self.cli("validate", str(path), expected=1)
            self.cli("validate", str(path.parent / "absent"), expected=1)

    def test_dirty_result_never_qualifies(self):
        result = self.result()
        result["kind"] = "qualification"
        result["provenance"]["dirty"] = True
        result["provenance"]["dirty_entries"] = [" M synthetic"]
        with self.assertRaisesRegex(ValueError, "dirty provenance"):
            driver.validate_result(result)

    def test_argparse_errors_return_usage_exit(self):
        for args in [[], ["run"], ["check", "--invalid"], ["run", "--output", "x", "--candidate", "x",
                    "--timing-slot", "x", "--iterations", "0"]]:
            with self.subTest(args=args), contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as failure:
                driver.main(args)
            self.assertEqual(failure.exception.code, 2)
        self.assertEqual(driver.positive("2"), 2)

    def test_exclusive_slot_diagnostic_writer_and_drift_failure(self):
        slot = os.environ.get("FORGELOGKIT_TIMING_SLOT")
        if not slot:
            self.skipTest("writer executes only in controller exclusive timing slot")
        sha = driver.command(["git", "rev-parse", "HEAD"])
        with tempfile.TemporaryDirectory(dir=ROOT / ".build") as temporary:
            arguments = ["run", "--output", temporary, "--candidate", sha, "--timing-slot", slot,
                         "--diagnostic", "--samples", "1", "--iterations", "3"]
            self.cli(*arguments)
            path = pathlib.Path(temporary) / "result.json"
            result = json.loads(path.read_text())
            self.assertEqual(result["kind"], "diagnostic")
            self.cli("validate", str(path))
            self.cli(*arguments, expected=1)
            path.unlink()
            sources = driver.source_manifest()
            with mock.patch.object(driver, "source_manifest", side_effect=[sources, {}]):
                _, error = self.cli(*arguments, expected=1)
            self.assertIn("source/toolchain changed during run", error)
            self.assertFalse(path.exists())


class CommandTrust(unittest.TestCase):
    def test_shell_metacharacters_stay_literal_and_candidate_cannot_execute(self):
        with tempfile.TemporaryDirectory() as temporary:
            marker = pathlib.Path(temporary) / "unexpected-command"
            operand = "$(touch " + str(marker) + "); `touch " + str(marker) + "`"
            self.assertEqual(driver.command(["/usr/bin/printf", "%s", operand]), operand)
            with self.assertRaisesRegex(ValueError, "full candidate"):
                driver.git_state(operand, True)
            self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
