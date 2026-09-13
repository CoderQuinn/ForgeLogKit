#!/bin/bash
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output=.build/objc-redaction
mkdir -p "$output"
xcrun clang -Wall -Wextra -Werror -I Sources/ForgeLogKitC \
    -include Tests/ObjCRedactionHarness/Capture.h \
    -c Sources/ForgeLogKitC/FLLogC.c -o "$output/FLLogC.o"
xcrun clang -Wall -Wextra -Werror -I Sources/ForgeLogKitC \
    -c Sources/ForgeLogKitC/FLRedaction.c -o "$output/FLRedaction.o"
xcrun clang -Wall -Wextra -Werror -fobjc-arc \
    -I Sources/ForgeLogKitC -I Sources/ForgeLogKitOC \
    Tests/ObjCRedactionHarness/main.m Sources/ForgeLogKitOC/FLLogOC.m \
    "$output/FLLogC.o" "$output/FLRedaction.o" -framework Foundation \
    -o "$output/test"
"$output/test"
