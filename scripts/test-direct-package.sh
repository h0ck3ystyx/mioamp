#!/bin/bash
# Inspect a built distribution without installing it or requesting privileges.
set -euo pipefail
cd "$(dirname "$0")/.."
PACKAGE="${1:?Usage: scripts/test-direct-package.sh PACKAGE.pkg}"
CHECK=$(mktemp -d "$PWD/build/package-check.XXXXXX")
trap 'rm -rf "$CHECK"' EXIT
pkgutil --expand-full "$PACKAGE" "$CHECK/expanded"
DOMAINS=$(/usr/sbin/installer -dominfo -pkg "$PACKAGE")
printf '%s\n' "$DOMAINS" | grep -Fx CurrentUserHomeDirectory >/dev/null
printf '%s\n' "$DOMAINS" | grep -Fx LocalSystem >/dev/null
/usr/bin/python3 - "$CHECK/expanded" <<'PY'
import pathlib
import plistlib
import sys
import xml.etree.ElementTree as ET
root = pathlib.Path(sys.argv[1])
dist = ET.parse(root / 'Distribution').getroot()
assert dist.find('domains').attrib == {
    'enable_anywhere': 'false', 'enable_currentUserHome': 'true', 'enable_localSystem': 'true'
}
assert not dist.findall('.//*[@auth]'), 'Authorization must be selected by domain'
assert dist.find('options').get('hostArchitectures') == 'arm64,x86_64'
assert dist.find('.//os-version').get('min') == '14.0'
component = root / 'MioAmp-component.pkg'
info = ET.parse(component / 'PackageInfo').getroot()
assert info.get('install-location') == '/'
assert info.get('relocatable') == 'false'
assert info.find('scripts') is None
assert not list(component.glob('Scripts*'))
payload = component / 'Payload'
assert {p.name for p in payload.iterdir()} == {'Applications'}, 'Payload must remain inside the selected domain'
app = payload / 'Applications/MioAmp.app'
assert app.is_dir()
assert (app / 'Contents/Resources/LICENSE').is_file()
app_info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert (app / 'Contents/Resources/AppIcon.icns').is_file()
assert (app / 'Contents/Resources/THIRD-PARTY-NOTICES.md').is_file()
assert (root / 'Resources/Welcome.html').is_file()
print('Package checks passed: both domains, fixed relative destination, no scripts, license and notices present')
PY
codesign --verify --deep --strict "$CHECK/expanded/MioAmp-component.pkg/Payload/Applications/MioAmp.app"
