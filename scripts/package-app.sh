#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
output_root="${1:-$repo_root/build}"
app_bundle="$output_root/MioAmp.app"
legacy_app_bundles=("$output_root/MacAmp.app" "$output_root/ChuckAmp.app")

cd "$repo_root"
export CLANG_MODULE_CACHE_PATH="$repo_root/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$repo_root/.build/ModuleCache"
swift build --disable-sandbox \
  --cache-path "$repo_root/.build/cache" \
  --config-path "$repo_root/.build/config" \
  --security-path "$repo_root/.build/security" \
  --configuration release \
  --product MioAmp
binary_path="$(swift build --disable-sandbox --cache-path "$repo_root/.build/cache" --config-path "$repo_root/.build/config" --security-path "$repo_root/.build/security" --configuration release --show-bin-path)/MioAmp"

rm -rf "$app_bundle" "${legacy_app_bundles[@]}"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
ditto "$binary_path" "$app_bundle/Contents/MacOS/MioAmp"
ditto "$repo_root/MioAmp/Resources/Info.plist" "$app_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${MIOAMP_BUNDLE_IDENTIFIER:-io.github.h0ck3ystyx.mioamp}" "$app_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${MIOAMP_VERSION:-1.0.0}" "$app_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${MIOAMP_BUILD_NUMBER:-1}" "$app_bundle/Contents/Info.plist"
ditto "$repo_root/MioAmp/Resources/PrivacyInfo.xcprivacy" "$app_bundle/Contents/Resources/PrivacyInfo.xcprivacy"
ditto "$repo_root/Skins" "$app_bundle/Contents/Resources/Skins"
ditto "$repo_root/LICENSE" "$app_bundle/Contents/Resources/LICENSE"
ditto "$repo_root/THIRD-PARTY-NOTICES.md" "$app_bundle/Contents/Resources/THIRD-PARTY-NOTICES.md"
xcrun actool "$repo_root/MioAmp/Resources/Assets.xcassets" \
  --compile "$app_bundle/Contents/Resources" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$output_root/assetcatalog-info.plist" \
  >/dev/null
codesign --force --sign - --entitlements "$repo_root/MioAmp/Resources/MioAmp.entitlements" "$app_bundle"
echo "$app_bundle"
