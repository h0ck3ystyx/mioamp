#!/bin/bash
# Developer ID distribution: personal/all-users installer and portable app ZIP.
set -euo pipefail
cd "$(dirname "$0")"
MODE="${1:-}"
case "$MODE" in ''|--check|--sign-only|--notarize-existing) ;; *) echo 'Usage: release.sh [--check | --sign-only | --notarize-existing DIRECTORY]' >&2; exit 1 ;; esac
: "${APPLICATION_IDENTITY:?Set Developer ID Application identity}"
: "${INSTALLER_IDENTITY:?Set Developer ID Installer identity}"
[[ "$APPLICATION_IDENTITY" == 'Developer ID Application: '* && "$INSTALLER_IDENTITY" == 'Developer ID Installer: '* ]] || { echo 'Developer ID certificates required' >&2; exit 1; }
TEAM="${APPLICATION_IDENTITY##* (}"; TEAM="${TEAM%)}"
[[ "$TEAM" =~ ^[A-Z0-9]{10}$ && "$INSTALLER_IDENTITY" == *" ($TEAM)" ]] || { echo 'Certificate teams must match' >&2; exit 1; }
for tool in xcodebuild notarytool stapler; do xcrun --find "$tool" >/dev/null; done
for identity in "$APPLICATION_IDENTITY" "$INSTALLER_IDENTITY"; do
  security find-identity -v -p basic | grep -F -- "\"$identity\"" >/dev/null || { echo "Missing identity: $identity" >&2; exit 1; }
done
if [[ "$MODE" != --sign-only ]]; then
  : "${NOTARY_PROFILE:?Set the name of a notarytool Keychain profile}"
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format plist >/dev/null
fi
[[ "$MODE" != --check ]] || { echo 'Signing and notarization prerequisites verified'; exit 0; }
export APPLICATION_IDENTITY INSTALLER_IDENTITY
if [[ "$MODE" == --notarize-existing ]]; then
  OUT="${2:?Supply the signed release directory}"
  OUT=$(cd "$OUT" && pwd)
  APP="$OUT/MioAmp.app"
  export MIOAMP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
  export MIOAMP_BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
else
  export MIOAMP_VERSION="${MIOAMP_VERSION:-1.0.0}" MIOAMP_BUILD_NUMBER="${MIOAMP_BUILD_NUMBER:-2}"
  [[ "$MIOAMP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$MIOAMP_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo 'Expected semantic version and positive build number' >&2; exit 1; }
  OUT="$PWD/build/releases/$MIOAMP_VERSION-$MIOAMP_BUILD_NUMBER"
  [[ ! -e "$OUT" ]] || { echo "Release directory already exists: $OUT" >&2; exit 1; }
  ./scripts/test.sh
  ./scripts/build-direct.sh "$OUT"
  APP="$OUT/MioAmp.app"
fi
MIOAMP_EXPECTED_ARCHS='arm64 x86_64' ./scripts/validate-app-bundle.sh "$APP" archive
DETAILS=$(codesign -d --verbose=4 "$APP" 2>&1)
printf '%s\n' "$DETAILS" | grep -Fx "Authority=$APPLICATION_IDENTITY" >/dev/null
printf '%s\n' "$DETAILS" | grep -Fx "TeamIdentifier=$TEAM" >/dev/null
printf '%s\n' "$DETAILS" | grep -E 'flags=.*\(.*runtime' >/dev/null
printf '%s\n' "$DETAILS" | grep '^Timestamp=' >/dev/null
PKG="$OUT/MioAmp-$MIOAMP_VERSION.pkg"
ZIP="$OUT/MioAmp-$MIOAMP_VERSION.zip"
echo 'Signed candidate; notarization is not complete. Do not distribute yet.' > "$OUT/STATUS.txt"
notarize() {
  local file="$1" label="$2" result=0 status='' submission=''
  xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --output-format plist > "$OUT/$label-notary.plist" || result=$?
  if plutil -lint "$OUT/$label-notary.plist" >/dev/null 2>&1; then
    status=$(/usr/libexec/PlistBuddy -c 'Print :status' "$OUT/$label-notary.plist" 2>/dev/null || true)
    submission=$(/usr/libexec/PlistBuddy -c 'Print :id' "$OUT/$label-notary.plist" 2>/dev/null || true)
  fi
  if [[ "$submission" =~ ^[[:xdigit:]-]{36}$ ]]; then
    xcrun notarytool log "$submission" --keychain-profile "$NOTARY_PROFILE" "$OUT/$label-notary-log.json" || true
  fi
  [[ "$result" == 0 && "$status" == Accepted ]] || { echo "Notarization failed: ${status:-unknown}. See $OUT/$label-notary.plist" >&2; return 1; }
}
if [[ "$MODE" != --sign-only ]]; then
  ditto -c -k --keepParent "$APP" "$OUT/app-submission.zip"
  notarize "$OUT/app-submission.zip" app
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
fi
# Rebuild final archives after stapling the application.
rm -f "$ZIP" "$PKG"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
./scripts/package-direct.sh "$APP" "$PKG"
./scripts/test-direct-package.sh "$PKG"
pkgutil --check-signature "$PKG"
if [[ "$MODE" != --sign-only ]]; then
  notarize "$PKG" installer
  xcrun stapler staple "$PKG"
  xcrun stapler validate "$PKG"
  spctl --assess --type install --verbose=2 "$PKG"
  echo 'Signed, notarized, stapled, and Gatekeeper-assessed.' > "$OUT/STATUS.txt"
fi
(cd "$OUT" && shasum -a 256 "MioAmp-$MIOAMP_VERSION.pkg" "MioAmp-$MIOAMP_VERSION.zip" > SHA256SUMS)
cat "$OUT/STATUS.txt"
echo "Release artifacts: $OUT"
