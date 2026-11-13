#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
readonly source_root="${repository_root}/Sources/"
readonly coverage_threshold="95.00"
readonly summary_directory="${repository_root}/.build/coverage"
readonly summary_path="${summary_directory}/production-summary.md"
readonly changed_base="${1:-}"
readonly source_data_path="${summary_directory}/production-files.json"

cd "${repository_root}"

for command_name in jq swift xcrun python3; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: required command '${command_name}' was not found" >&2
        exit 1
    fi
done

swift package clean
swift test \
    --enable-code-coverage \
    -Xcc -fprofile-instr-generate \
    -Xcc -fcoverage-mapping

readonly coverage_path="$(swift test --show-codecov-path)"
if [[ ! -s "${coverage_path}" ]]; then
    echo "error: SwiftPM did not produce a coverage report" >&2
    exit 1
fi

mkdir -p "${summary_directory}"
readonly binary_directory="$(swift build --show-bin-path)"
readonly test_binary="${binary_directory}/ForgeLogKitPackageTests.xctest/Contents/MacOS/ForgeLogKitPackageTests"
xcrun llvm-cov export "${test_binary}" \
    -instr-profile="$(dirname "${coverage_path}")/default.profdata" \
    -format=lcov > "${summary_directory}/swiftpm.lcov"
bash "${script_directory}/test-objc-redaction.sh" --coverage

jq \
    --arg source_root "${source_root}" \
    '[
        .data[].files[]
        | select(.filename | startswith($source_root))
        | (.filename | ltrimstr($source_root)) as $relative_path
        | {
            target: ($relative_path | split("/")[0]),
            file: $relative_path,
            covered: .summary.lines.covered,
            count: .summary.lines.count
        }
    ] | sort_by(.target, .file)' \
    "${coverage_path}" > "${source_data_path}"

if [[ "$(jq 'length' "${source_data_path}")" -eq 0 ]]; then
    echo "error: coverage report contains no production files under Sources/" >&2
    exit 1
fi

for expected_target in ForgeLogKit ForgeLogKitC ForgeLogKitOC; do
    if ! jq -e \
        --arg target "${expected_target}" \
        'any(.[]; .target == $target)' \
        "${source_data_path}" >/dev/null; then
        echo "error: production target '${expected_target}' is absent from coverage" >&2
        exit 1
    fi
done

read -r total_covered total_count < <(
    jq -r \
        '[(map(.covered) | add), (map(.count) | add)] | @tsv' \
        "${source_data_path}"
)
readonly total_percent="$(
    awk \
        -v covered="${total_covered}" \
        -v count="${total_count}" \
        'BEGIN { printf "%.2f", 100 * covered / count }'
)"

{
    echo "# Production source coverage"
    echo
    echo "Only files under \`Sources/\` are counted; tests and test support are excluded."
    echo
    echo "| Target | Covered lines | Total lines | Line coverage |"
    echo "| --- | ---: | ---: | ---: |"
    while IFS=$'\t' read -r target covered count; do
        percent="$(
            awk \
                -v covered="${covered}" \
                -v count="${count}" \
                'BEGIN { printf "%.2f", 100 * covered / count }'
        )"
        printf '| %s | %s | %s | %s%% |\n' \
            "${target}" "${covered}" "${count}" "${percent}"
    done < <(
        jq -r '
            group_by(.target)[]
            | [.[0].target, (map(.covered) | add), (map(.count) | add)]
            | @tsv
        ' "${source_data_path}"
    )
    printf '| **Total** | **%s** | **%s** | **%s%%** |\n' \
        "${total_covered}" "${total_count}" "${total_percent}"
    echo
    echo "Required total line coverage: ${coverage_threshold}%"
    echo
    echo "## Files"
    echo
    echo "| Production file | Covered lines | Total lines | Line coverage |"
    echo "| --- | ---: | ---: | ---: |"
    while IFS=$'\t' read -r file covered count; do
        percent="$(
            awk \
                -v covered="${covered}" \
                -v count="${count}" \
                'BEGIN { printf "%.2f", 100 * covered / count }'
        )"
        printf '| `%s` | %s | %s | %s%% |\n' \
            "${file}" "${covered}" "${count}" "${percent}"
    done < <(
        jq -r '.[] | [.file, .covered, .count] | @tsv' "${source_data_path}"
    )
} > "${summary_path}"

cat "${summary_path}"

if ! awk \
    -v actual="${total_percent}" \
    -v minimum="${coverage_threshold}" \
    'BEGIN { exit !(actual >= minimum) }'; then
    echo "error: production line coverage ${total_percent}% is below ${coverage_threshold}%" >&2
    exit 1
fi

echo "Coverage gate passed: ${total_percent}% >= ${coverage_threshold}%"

if [[ -n "${changed_base}" ]]; then
    python3 - "${repository_root}" "${changed_base}" \
        "${summary_directory}/swiftpm.lcov" \
        "${repository_root}/.build/objc-redaction/harness.lcov" <<'PYTHON'
import json
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
base = sys.argv[2]
# Resolve a commit rather than silently accepting a missing/ambiguous base.
subprocess.run(["git", "rev-parse", "--verify", base + "^{commit}"], cwd=root,
               check=True, stdout=subprocess.DEVNULL)
coverage = {}
for filename in sys.argv[3:]:
    current = None
    for line in Path(filename).read_text().splitlines():
        if line.startswith("SF:"):
            current = str(Path(line[3:]).resolve().relative_to(root))
            coverage.setdefault(current, {})
        elif line.startswith("DA:") and current is not None:
            number, hits, *_ = line[3:].split(",")
            lines = coverage[current]
            lines[int(number)] = max(lines.get(int(number), 0), int(hits))
        elif line == "end_of_record":
            current = None

diff = subprocess.run(
    ["git", "diff", "--no-ext-diff", "--unified=0", base, "--", "Sources", "Tests"],
    cwd=root, check=True, capture_output=True, text=True
).stdout
changed = {}
current = None
for line in diff.splitlines():
    if line.startswith("+++ b/"):
        current = line[6:]
    elif line.startswith("@@") and current is not None:
        match = re.search(r"\+(\d+)(?:,(\d+))? @@", line)
        if not match:
            raise SystemExit("error: cannot parse changed-line hunk")
        start = int(match[1])
        count = int(match[2]) if match[2] is not None else 1
        changed.setdefault(current, set()).update(range(start, start + count))

rows = []
for filename, additions in sorted(changed.items()):
    if Path(filename).suffix not in {".swift", ".c", ".m"} or not additions:
        continue
    if filename not in coverage:
        raise SystemExit("error: changed authored source missing from coverage: " + filename)
    owned = additions & coverage[filename].keys()
    missed = sorted(number for number in owned if coverage[filename][number] == 0)
    rows.append(dict(file=filename, covered=len(owned) - len(missed), count=len(owned), missed=missed))

result = dict(base=base, scope="added LLVM LCOV-owned lines in Sources/ and Tests/ (.swift/.c/.m)", files=rows)
for label, selected in (
    ("production", [row for row in rows if row["file"].startswith("Sources/")]),
    ("tests_and_harness", [row for row in rows if row["file"].startswith("Tests/")]),
):
    covered = sum(row["covered"] for row in selected)
    count = sum(row["count"] for row in selected)
    result[label] = dict(covered=covered, count=count)
    print(f"Changed {label} LLVM lines: {covered}/{count}")
    if count and covered / count < .95:
        raise SystemExit("error: changed executable line coverage is below 95%")
(root / ".build/coverage/changed-lines.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
PYTHON
fi
