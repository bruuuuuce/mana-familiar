# Release readiness

This repository is ready for **human release review**, not publication. No
tag, package upload, signing identity, notarization credential, or release
asset is created by its CI workflow.

## Source build

```sh
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build macos --debug
```

The GitHub Actions macOS workflow runs this same validation sequence for pull
requests and pushes to `main` and `develop`.

## Ad-hoc local build

For a local, non-distributed artifact, build a release app and inspect it on
the same machine:

```sh
flutter build macos --release
open build/macos/Build/Products/Release/Mana\ Familiar.app
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
