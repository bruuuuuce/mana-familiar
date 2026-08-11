# Consumer architecture

Mana Familiar is a read-only desktop consumer of Mana Learning
Journey artifacts. It owns presentation, navigation, source viewing, diagram
viewing, and local UI preferences. Mana owns Journey IDs, append-only
persistence, validation, graph materialization, concepts, and expansion
semantics.

## Supported producer boundary

Given `--project-root`, the app reads the selected target project's Journey
directory at:

```text
.mana/learning/journeys/<journey-id>/
```

It invokes only these Mana producer entry points under `--mana-root`:

- `scripts/mana-journey.sh --project-root <project> materialize <journey>`
  to obtain `mana.learning.graph/v1` JSON;
- `scripts/mana-concepts.sh ... labels --journey <journey> --node <node> --json`
  for canonical labels;
- `scripts/mana-expand.sh ... request --journey <journey> --node <node>` for
  an explicitly user-requested bounded expansion.

The app may watch a selected Journey directory and read a diagram asset named
by the materialized graph. It resolves source anchors only below the supplied
project root and uses Git only to display source snapshots. These are consumer
operations, not a dependency on Mana source layout.

## Ownership and persistence

The app never parses or writes individual Journey record files. It treats
Mana's Journey schema and materialized graph as authoritative. User interface
preferences are stored outside the project: in macOS Application Support or
the platform configuration directory. They are deliberately not Mana
artifacts.

Mana Familiar pins its accepted consumer contract locally in
[`artifact-compatibility.md`](artifact-compatibility.md). Changes to the
materialized graph or the CLI commands above require a compatible producer
release and a corresponding Mana Familiar update. The app rejects missing or
unsupported graph schema identifiers before rendering.
