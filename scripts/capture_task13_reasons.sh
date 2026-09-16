#!/bin/bash
# Task 13: real simulator UI, generated fixture traces, light-only product.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$ROOT/docs/device-evidence/product-v2/task13"
SIMULATOR="${PACKWISE_SIMULATOR:-iPhone 17 Pro}"
APP_PATH="$(xcodebuild -project "$ROOT/ios/PackWise.xcodeproj" -scheme PackWise -destination "platform=iOS Simulator,name=$SIMULATOR" -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')/PackWise.app"
mkdir -p "$OUTPUT"
xcrun simctl boot "$SIMULATOR" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR" -b
xcrun simctl install "$SIMULATOR" "$APP_PATH"
xcrun simctl ui "$SIMULATOR" appearance light
for size in large accessibility-large; do
    xcrun simctl ui "$SIMULATOR" content_size "$size"
    for screen in languageSolo languageMulti languageSingle languageCombined languageWeather languageActivity languageDevice languageChild languageShared languageQuantity languageGroup; do
        xcrun simctl terminate "$SIMULATOR" com.packwiseapp.app 2>/dev/null || true
        xcrun simctl launch "$SIMULATOR" com.packwiseapp.app -PackWiseScreen "$screen"
        sleep 3
        xcrun simctl io "$SIMULATOR" screenshot --type=png "$OUTPUT/$screen-$size.png"
    done
done
xcrun simctl ui "$SIMULATOR" content_size large
