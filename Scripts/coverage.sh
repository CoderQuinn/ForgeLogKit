#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
readonly source_root="${repository_root}/Sources/"
readonly coverage_threshold="95.00"
readonly summary_directory="${repository_root}/.build/coverage"
readonly summary_path="${summary_directory}/production-summary.md"
readonly source_data_path="${summary_directory}/production-files.json"

cd "${repository_root}"

for command_name in jq swift; do
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
