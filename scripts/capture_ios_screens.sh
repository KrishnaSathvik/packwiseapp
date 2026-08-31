#!/bin/bash
# Photograph PackWise screens from the running simulator.
#
# The UI conformance pass has to be checked against design/ui-flow-overview.png
# in light mode, dark mode, and at an accessibility text size. ImageRenderer
# cannot do this — it refuses List, ScrollView, and NavigationStack — so the
# screens are captured from the real app, seeded by the Debug-only
# -PackWiseScreen launch argument.
#
#   scripts/capture_ios_screens.sh <output-dir> <screen> [screen ...]
#
# Screens are the cases of DebugPreviewScreen, e.g. tripDetail, packingList.

set -euo pipefail

if [ $# -lt 2 ]; then
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
fi

OUTPUT_DIR="$1"
shift
SCREENS=("$@")

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SIMULATOR="${PACKWISE_SIMULATOR:-iPhone 17 Pro}"
BUNDLE_ID="com.packwiseapp.app"

mkdir -p "$OUTPUT_DIR"

APP_PATH="$(xcodebuild -project "$REPO/ios/PackWise.xcodeproj" -scheme PackWise \
    -destination "platform=iOS Simulator,name=$SIMULATOR" \
    -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')/PackWise.app"

if [ ! -d "$APP_PATH" ]; then
    echo "error: no built app at $APP_PATH — run xcodebuild build first" >&2
    exit 1
fi

echo "booting $SIMULATOR"
xcrun simctl boot "$SIMULATOR" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR" -b >/dev/null 2>&1 || true
xcrun simctl install "$SIMULATOR" "$APP_PATH"

# suffix:appearance:content-size
VARIANTS=(
    "light:light:large"
    "dark:dark:large"
    "xl-type:light:accessibility-large"
)

for screen in "${SCREENS[@]}"; do
    for variant in "${VARIANTS[@]}"; do
        suffix="${variant%%:*}"
        rest="${variant#*:}"
        appearance="${rest%%:*}"
        content_size="${rest#*:}"

        xcrun simctl ui "$SIMULATOR" appearance "$appearance" >/dev/null
        xcrun simctl ui "$SIMULATOR" content_size "$content_size" >/dev/null

        xcrun simctl terminate "$SIMULATOR" "$BUNDLE_ID" 2>/dev/null || true
        xcrun simctl launch "$SIMULATOR" "$BUNDLE_ID" -PackWiseScreen "$screen" >/dev/null

        # Let the first frame settle; destination imagery resolves async.
        sleep 4

        target="$OUTPUT_DIR/$screen-$suffix.png"
        xcrun simctl io "$SIMULATOR" screenshot --type=png "$target" >/dev/null 2>&1
        echo "captured $target"
    done
done

xcrun simctl terminate "$SIMULATOR" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl ui "$SIMULATOR" appearance light >/dev/null
xcrun simctl ui "$SIMULATOR" content_size large >/dev/null
