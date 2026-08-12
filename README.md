<p align="center">
  <img src="assets/branding/mana-familiar-logo.png" alt="Mana Familiar" width="280">
</p>

# Mana Familiar

Mana Familiar is the desktop companion for exploring Mana learning
journeys, evidence graphs, source references, and architecture context.

See the [product boundary](docs/product-boundary.md) for the read-only client
scope and the versioned-contract direction.

Mana is the producer: it creates and validates Journey artifacts. This
repository is the consumer/explorer: it renders those artifacts and can invoke
the documented Mana commands for materialization, concept labels, and bounded
explanation requests. It does not write Journey records or source code.

## Development

Requirements: Flutter with macOS desktop support. A Mana checkout or
installation is required only for producer-backed mode; direct artifact mode
works with this repository alone.

### Open a materialized artifact directly

Any compatible `mana.learning.graph/v1` JSON artifact can be opened read-only
without installing Mana:

```sh
flutter pub get
flutter run -d macos \
  --dart-entrypoint-args=--artifact \
  --dart-entrypoint-args=/path/to/materialized-journey.json \
  --dart-entrypoint-args=--project-root \
  --dart-entrypoint-args=/path/to/source-project
```

`--project-root` is optional when no source anchors need to be resolved.
Diagram paths in the artifact are resolved relative to the artifact directory.
`--fixture` remains a backwards-compatible alias for `--artifact`.
Artifact-derived source and diagram paths are containment-checked before any
file is read; see [Artifact compatibility](docs/artifact-compatibility.md).

### Use a Mana producer installation

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
Journey artifacts are being explored. `--mana-root` identifies any compatible
Mana installation that supplies the producer commands; it does not need to be
a sibling checkout. Supplying both flags is the portable producer-backed
invocation. When omitted, the app only performs local ancestor discovery for
convenience.

### Open a saved Mana inspect response

For standalone demos or testing of the project read model, open a saved
versioned Mana inspect response without a Mana checkout:

```sh
flutter run -d macos \
  --dart-entrypoint-args=--inspect-snapshot \
  --dart-entrypoint-args=/path/to/mana-inspect-response.json
```

The inspect client negotiates project capabilities before optional operations;
see [Mana inspect compatibility](docs/mana-inspect-compatibility.md).

Run the complete validation suite with:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build macos --debug
```

## Contract

This consumer supports exactly `mana.learning.graph/v1`. Missing or unsupported
schema identifiers and malformed artifacts are rejected with explicit errors.
The local compatibility rules are pinned in
[Artifact compatibility](docs/artifact-compatibility.md); they can be reviewed
without access to the Mana repository.

Producer-backed mode consumes the deterministic materialization emitted by
`scripts/mana-journey.sh materialize`, plus the documented concept-label and
expansion request commands. See the
[consumer architecture note](docs/architecture.md) for the boundary.

## Development fixture

For the repository's deterministic branching/cycle fixture:

```sh
flutter run -d macos \
  --dart-entrypoint-args=--artifact \
  --dart-entrypoint-args=test/fixtures/complex_journey_fixture.json
```

The fixture is materialized Journey JSON and never persists data under `.mana`.

## Supported platforms

macOS desktop is the supported application target. Web scaffolding is retained
for possible future work, but browser runtime is not supported because source
resolution, Git snapshots, filesystem watching, and producer commands require
desktop APIs.

## License

Mana Familiar is available under the [MIT License](LICENSE).
