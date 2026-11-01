# Signed releases outside the Mac App Store

MioAmp's direct release follows the Peekdown packaging model: a universal Apple Silicon/Intel app, a signed ZIP, and one signed installer offering personal or all-users installation. Requires macOS 14 or later.

## Installation choices

- **Install for me only** maps the payload to `~/Applications/MioAmp.app` and does not request administrator authorization under normal macOS policy.
- **Install for all users of this computer** maps it to `/Applications/MioAmp.app` and requires administrator authorization.
- If Installer skips Destination Select, click **Change Install Location…** on the Installation Type screen.
- The ZIP is an alternative: extract it and move MioAmp.app to `~/Applications`. Create that folder if needed.

No privileged helper or installation script is included. Upgrades replace the copy in the selected domain; they do not search for and relocate another copy. A personal install does not remove a shared installation. Managed-device policies may restrict installations independently of these choices.

## Local signing setup

Use Xcode with Swift 6.2 or later and valid Developer ID Application and Developer ID Installer identities with private keys from the same team. Apple Distribution certificates for the App Store do not replace these identities.

```sh
export APPLICATION_IDENTITY='Developer ID Application: Charles Sinnett (7ZH96S5LF4)'
export INSTALLER_IDENTITY='Developer ID Installer: Charles Sinnett (7ZH96S5LF4)'
export MIOAMP_VERSION=1.0.0
export MIOAMP_BUILD_NUMBER=2
export NOTARY_PROFILE=MioAmp-notary
```

Choose a new build number above previously distributed builds. If an existing same-team notarization profile is available (including one used for Peekdown), its name can be used instead. No password or private key belongs in source control.

Create a profile if necessary. This command prompts for your Apple account and app-specific password; do not paste the password into a chat or source file:

```sh
xcrun notarytool store-credentials MioAmp-notary --team-id 7ZH96S5LF4
./release.sh --check
./release.sh
```

The full release runs the automated tests, archives both architectures with signing disabled, adds the license and complete dependency notices, signs using Developer ID with hardened runtime and a secure timestamp, notarizes and staples the app, then builds, signs, notarizes and staples the installer. It verifies the app signature, entitlements, architectures, installer domains and payload, plus Gatekeeper assessments of the app and installer. The ZIP is created after the app is stapled.

Outputs are under `build/releases/<version>-<build>/`:

- `MioAmp-<version>.pkg`
- `MioAmp-<version>.zip`
- `SHA256SUMS`
- `STATUS.txt`, the signed app, archive, and Apple submission results/logs

Only distribute a run whose `STATUS.txt` says **Signed, notarized, stapled, and Gatekeeper-assessed.** Existing release directories are not overwritten by a new build.

## Build while notarization credentials are unavailable

```sh
./release.sh --sign-only
```

This runs the same tests, universal build, signing and installer validation, but does not contact Apple's notary service. Its artifacts are signed candidates, not verified distribution releases. Once credentials are ready, finish the same candidate without rebuilding:

```sh
export NOTARY_PROFILE=MioAmp-notary
./release.sh --notarize-existing build/releases/1.0.0-2
```

The resume command revalidates the signed app, notarizes and staples it, recreates the installer and ZIP, and then notarizes and staples the installer. If a submission fails, use the ID saved in `app-notary.plist` or `installer-notary.plist` with `xcrun notarytool info ID --keychain-profile PROFILE`. Inspect the saved log before retrying; don't publish files from a failed run.

## GitHub Actions

The **Signed direct release** workflow is manually dispatched with version and build-number inputs. It uses a temporary signing keychain and creates a **draft** GitHub Release only after notarization and verification succeed. Run it from the intended release commit on main. No signing secrets were copied from Peekdown or stored in this repository.

Configure these repository Actions secrets:

| Secret | Value |
| --- | --- |
| `APPLICATION_CERT_BASE64` | Base64-encoded Developer ID Application `.p12`, including its private key |
| `INSTALLER_CERT_BASE64` | Base64-encoded Developer ID Installer `.p12`, including its private key |
| `CERT_PASSWORD` | Password protecting both `.p12` exports |
| `NOTARY_APPLE_ID` | Apple account used for notarization |
| `NOTARY_APP_PASSWORD` | Apple app-specific password |
| `NOTARY_TEAM_ID` | Matching Apple Developer team ID |

Keep certificate exports offline and enter them through GitHub's encrypted secret controls. Secret values cannot be read back or copied from another repository through GitHub's API. The workflow does not run on pull requests and does not update a Homebrew tap.

## Acceptance before publication

The automated installer check expands the payload without installing it. It confirms both domains, the relative `Applications/` destination, no installer scripts, non-relocating upgrades, and included licenses. It does not prove the complete interactive installation flow.

On clean Macs or VMs, test personal installation with a standard non-admin account, all-users installation with administrator authorization, upgrades in both destinations, and launching the stapled app offline with normal Gatekeeper settings. Check local-file access and restored bookmarks. Verify playback on Apple Silicon, Intel, and the oldest supported macOS. Do not bypass Gatekeeper or modify quarantine attributes to make a release pass.

## App Store builds

The existing `scripts/archive-app-store.sh` and `scripts/export-app-store.sh` remain the App Store workflow. Direct-distribution `.pkg` files use Developer ID Installer, not Mac App Store signing, and must not be uploaded as App Store builds.

References: [Apple Developer ID](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/) and [Apple notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
