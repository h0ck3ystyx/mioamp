#!/bin/bash
# Build a universal app and sign it for distribution outside the Mac App Store.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${APPLICATION_IDENTITY:?Set Developer ID Application identity}"
[[ "$APPLICATION_IDENTITY" == 'Developer ID Application: '* ]] || { echo 'Developer ID Application identity required' >&2; exit 1; }
OUT="${1:?Usage: scripts/build-direct.sh NEW_OUTPUT_DIRECTORY}"
[[ ! -e "$OUT" ]] || { echo "Output already exists: $OUT" >&2; exit 1; }
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
export MIOAMP_VERSION="${MIOAMP_VERSION:-1.0.0}" MIOAMP_BUILD_NUMBER="${MIOAMP_BUILD_NUMBER:-2}"
MIOAMP_ALLOW_SIGNING=0 ./scripts/archive-app-store.sh "$OUT/MioAmp.xcarchive"
APP="$OUT/MioAmp.app"
ditto "$OUT/MioAmp.xcarchive/Products/Applications/MioAmp.app" "$APP"
ditto LICENSE "$APP/Contents/Resources/LICENSE"
ditto THIRD-PARTY-NOTICES.md "$APP/Contents/Resources/THIRD-PARTY-NOTICES.md"
[[ ! -f "$APP/Contents/embedded.provisionprofile" ]] || { echo 'Unexpected App Store provisioning profile' >&2; exit 1; }
codesign --force --sign "$APPLICATION_IDENTITY" --options runtime --timestamp \
  --entitlements MioAmp/Resources/MioAmp.entitlements "$APP"
MIOAMP_EXPECTED_ARCHS='arm64 x86_64' ./scripts/validate-app-bundle.sh "$APP" archive
DETAILS=$(codesign -d --verbose=4 "$APP" 2>&1)
printf '%s\n' "$DETAILS" | grep -Fx "Authority=$APPLICATION_IDENTITY" >/dev/null
printf '%s\n' "$DETAILS" | grep -E 'flags=.*\(.*runtime' >/dev/null
printf '%s\n' "$DETAILS" | grep '^Timestamp=' >/dev/null
codesign -d --entitlements :- "$APP" > "$OUT/entitlements.plist" 2>/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$OUT/entitlements.plist" 2>/dev/null || true)" != true ]]
echo "Developer ID signed app: $APP"
