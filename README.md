# MioAmp

MioAmp is a native Mac audio-player prototype inspired by classic Winamp's compact, modular feel. Product behavior is defined in [PRODUCT-DESIGN.md](PRODUCT-DESIGN.md); implementation sequencing and acceptance criteria are in [BUILD-PLAN.md](BUILD-PLAN.md). The path from the current MVP candidate to TestFlight and App Review is defined in [docs/APP-STORE-RELEASE-PLAN.md](docs/APP-STORE-RELEASE-PLAN.md).

## Requirements

- Apple-silicon or Intel Mac
- macOS 14 or newer
- Xcode 26.2 / Swift 6.2.3 (the first verified toolchain)

SwiftPM resolves the pinned ZIPFoundation 0.9.20 dependency used for safe `.mioampskin` archives. No personal signing identity is required for a local build.

## Build and test

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/package-app.sh
./scripts/validate-app-bundle.sh
open build/MioAmp.app
```

The package script creates a locally runnable, ad-hoc-signed app at `build/MioAmp.app`. It is a development artifact, not an App Store-signed or notarized public release. `Package.swift` is the current source and Xcode build graph; open it directly in Xcode to use the generated MioAmp scheme.

The native `MioAmp-AppStore` scheme in `MioAmp.xcodeproj` is the archive and managed-signing path. This command creates and validates an unsigned archive without requiring personal credentials:

```sh
./scripts/archive-app-store.sh
```

For an authorized signing environment, set `MIOAMP_ALLOW_SIGNING=1`; Team ID `7ZH96S5LF4` and bundle ID `io.github.h0ck3ystyx.mioamp` are configured in the project. Optional `MIOAMP_DEVELOPMENT_TEAM`, `MIOAMP_BUNDLE_IDENTIFIER`, `MIOAMP_VERSION`, and `MIOAMP_BUILD_NUMBER` values override release settings. `./scripts/export-app-store.sh` lets Xcode resolve cloud-managed distribution certificates and the matching profile, then validates the signed App Store Connect `.pkg` without uploading it. The prepared metadata, privacy, review, and submission packet is in `docs/app-store/`.

## Current state

The MVP candidate plays the full tested local format matrix through a bounded native audio pipeline; provides player, playlist, equalizer, and compact windows; imports and exports playlists; keeps named playlists; restores playback and presentation state paused; handles system media commands; and includes Studio Graphite, Paper, Terminal, accent variants, and validated `.mioampskin` packages. See `docs/TEST-REPORT.md` for current evidence and checks that still need physical or external access.

Shared types and service boundaries live in `Packages/MioAmpKit/Sources/Contracts`. Feature agents own their matching source folders. Only the coordinator changes `Package.swift`, application composition, shared contracts, dependency resolution, or packaging scripts.

## License

MioAmp's original source, documentation, and artwork are available under the [MIT License](LICENSE), copyright 2026 Chuck Sinnett. Dependencies retain their own licenses; complete distribution notices are in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## Signed downloads outside the App Store

The [direct release guide](RELEASE.md) covers Developer ID signing, notarization, and repeatable releases. The installer offers **Install for me only** (`~/Applications`, no administrator authorization under normal macOS policy) and **Install for all users** (`/Applications`, administrator authorization). A ZIP supports manual installation into `~/Applications`. Both artifacts must complete notarization before public distribution.

Use `./release.sh --check` to verify your signing setup and `./release.sh` to build. The manually triggered **Signed direct release** GitHub Actions workflow creates a draft release after successful notarization and package verification.
