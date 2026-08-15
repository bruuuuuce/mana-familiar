# Release readiness

This repository publishes unsigned desktop artifacts when a GitHub Release is
published. It does not create a tag, provide a signing identity, or perform
Apple notarization.

## Source build

```sh
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build macos --debug
flutter build windows --release
```

The GitHub Actions macOS workflow runs the validation sequence for pull
requests and pushes to `main` and `develop`.

## Published release artifacts

Publishing a GitHub Release triggers the `Release artifacts` workflow. It
builds and attaches these assets to that same release:

- `Mana-Familiar-macos.zip`, containing the macOS `.app` bundle;
- `Mana-Familiar-windows-x64.zip`, containing the Windows executable together
  with its required DLLs and data files;
- one SHA-256 checksum file for each archive.

Artifacts are unsigned. Windows users may receive a SmartScreen warning, and
macOS users may receive a Gatekeeper warning until a release owner supplies
the required signing and notarization credentials.

## Ad-hoc local build

For a local, non-distributed artifact, build a release app and inspect it on
the same machine:

```sh
flutter build macos --release
open build/macos/Build/Products/Release/Mana\ Familiar.app
```

On Windows, build and run the complete release directory rather than copying
only the executable:

```powershell
flutter build windows --release
start build\windows\x64\runner\Release\mana_familiar.exe
```

Ad-hoc signing, when required by a local environment, is a human release-team
operation. Do not add identities or certificates to this repository.

## Future Developer ID and notarization

Before a public macOS release, a release owner must provide a Developer ID
identity outside the repository, sign with hardened runtime, submit the
resulting archive through Apple's notarization tooling, staple the accepted
ticket, and validate on a clean macOS account. This document makes no claim
that those steps have been performed.

## F10 verification evidence

`test/performance_regression_test.dart` constructs a deterministic catalog of
2,400 mixed historical artifacts (including cycles, unknown/malformed and
oversized entries, stale/missing source references, and learning candidates).
It reports local parse-and-inbox-derivation timing in test logs and applies a
five-second regression bound. The timing is a CI/test-environment observation,
not a general product performance claim.

Security regressions cover safe direct-artifact and diagram paths, symlink and
traversal rejection, malformed inspect responses, bounded payload rendering,
inert Markdown, structured process arguments, and CLI-handoff argument
validation. The in-memory detail cache is revision-keyed, capped at 24 entries,
and discarded when the process exits.
