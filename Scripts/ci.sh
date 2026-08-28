#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"

cd "${repository_root}"

echo "== Swift toolchain =="
swift --version
echo
echo "== Xcode toolchain =="
xcodebuild -version
echo
echo "== Host platform =="
sw_vers
uname -a

echo
echo "== Clean dependency resolution =="
swift package reset
swift package resolve

echo
echo "== Debug build and tests =="
swift build --configuration debug
swift test --configuration debug

echo
echo "== Release build and tests =="
swift build --configuration release
swift test --configuration release

echo
echo "== Strict concurrency compile and tests =="
swift test \
    -Xswiftc -strict-concurrency=complete \
    -Xswiftc -warnings-as-errors

echo
echo "== Production coverage gate =="
"${script_directory}/coverage.sh"
