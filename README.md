# Mana Learning Explorer

Mana Learning Explorer is the desktop companion for exploring Mana learning
journeys, evidence graphs, source references, and architecture context.

Mana is the producer: it creates and validates Journey artifacts. This
repository is the consumer/explorer: it renders those artifacts and can invoke
the documented Mana commands for materialization, concept labels, and bounded
explanation requests. It does not write Journey records or source code.

## Development

Requirements: Flutter with macOS desktop support, a Mana checkout or
installation, and a Mana-enabled target project containing `.mana/learning`.

```sh
flutter pub get
flutter run -d macos \
  --dart-entrypoint-args=--project-root \
  --dart-entrypoint-args=/path/to/target-project \
  --dart-entrypoint-args=--mana-root \
  --dart-entrypoint-args=/path/to/mana \
  --dart-entrypoint-args=--journey \
  --dart-entrypoint-args=jrn_…
```

`--project-root` identifies the target project whose source anchors and
Journey artifacts are being explored. `--mana-root` identifies the Mana
installation that supplies the producer commands. Supplying both flags is the
portable, supported invocation. When omitted, the app only performs local
ancestor discovery for convenience; it never imports or assumes a sibling
Mana source tree.

Run checks with:

```sh
flutter analyze
flutter test
```

## Contract

The authoritative producer contract remains in the Mana repository:
`docs/standards/mana-learning-journey-v0.schema.json` and
`docs/standards/mana-learning-journey-v0.md`. This app consumes the
deterministic `mana.learning.graph/v1` materialization emitted by
`scripts/mana-journey.sh materialize`, plus the documented concept-label and
expansion request commands. See [the local architecture note](docs/architecture.md)
for the consumer boundary.

## Development fixture

For a deterministic UI-only fixture with no Mana installation required:

```sh
flutter run -d macos \
  --dart-entrypoint-args=--fixture \
  --dart-entrypoint-args=test/fixtures/complex_journey_fixture.json
```

The fixture is materialized Journey JSON and never persists data under
`.mana`.
