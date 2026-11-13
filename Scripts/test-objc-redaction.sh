#!/bin/bash
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output=.build/objc-redaction
mkdir -p "$output"
coverage_flags=(-g)
case "${1:-}" in
    "") ;;
    --coverage) coverage_flags+=(-fprofile-instr-generate -fcoverage-mapping) ;;
    *) echo "usage: $0 [--coverage]" >&2; exit 2 ;;
esac
xcrun clang "${coverage_flags[@]}" -Wall -Wextra -Werror -I Sources/ForgeLogKitC \
    -include Tests/ObjCRedactionHarness/Capture.h \
    -c Sources/ForgeLogKitC/FLLogC.c -o "$output/FLLogC.o"
xcrun clang "${coverage_flags[@]}" -Wall -Wextra -Werror -I Sources/ForgeLogKitC \
    -c Sources/ForgeLogKitC/FLRedaction.c -o "$output/FLRedaction.o"
xcrun clang "${coverage_flags[@]}" -Wall -Wextra -Werror -fobjc-arc \
    -I Sources/ForgeLogKitC -I Sources/ForgeLogKitOC \
    Tests/ObjCRedactionHarness/main.m Sources/ForgeLogKitOC/FLLogOC.m \
    "$output/FLLogC.o" "$output/FLRedaction.o" -framework Foundation \
    -o "$output/test"
if [[ "${1:-}" == --coverage ]]; then
    LLVM_PROFILE_FILE="$output/harness.profraw" "$output/test" Tests/ObjCRedactionHarness/canaries.json
    xcrun llvm-profdata merge -sparse "$output/harness.profraw" -o "$output/harness.profdata"
    xcrun llvm-cov export "$output/test" -instr-profile="$output/harness.profdata" -format=lcov > "$output/harness.lcov"
else
    "$output/test" Tests/ObjCRedactionHarness/canaries.json
fi
