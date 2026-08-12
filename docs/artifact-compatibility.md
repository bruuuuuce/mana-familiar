# Materialized artifact compatibility

Mana Familiar is a read-only consumer of materialized Journey graph
JSON. This document pins the compatibility boundary implemented by this
repository so a consumer build does not depend on documentation from another
checkout.

## Supported schema

The only accepted top-level schema identifier is:

```json
"schema": "mana.learning.graph/v1"
```

The `schema` field is mandatory. Missing identifiers and every other version
are rejected before the graph is rendered. A future schema requires an
explicit Mana Familiar change and tests; compatibility is never inferred from a
version prefix.

## Required envelope

A compatible artifact has:

- a top-level JSON object;
- the exact `schema` above;
- a `journey` object with a non-empty string `id`;
- a non-empty `nodes` array containing JSON objects.

When present, `edges`, `anchors`, `evidence`, `explanations`, `hypotheses`,
`hypothesis_assessments`, `concept_occurrences`, `timeline_events`, `diagrams`,
`traversals`, and `cycle_regions` must be arrays of JSON objects. Unknown fields
are preserved and ignored by readers that do not understand them.

## Loading modes

Direct artifact mode uses `--artifact <file>`. It does not invoke Mana. Source
anchors resolve below `--project-root`; diagram assets resolve relative to the
artifact file. `--fixture` is a backwards-compatible alias.

## Path and read safety

Artifact-derived source anchors and diagram asset paths are untrusted. They
must be non-empty relative paths using `/` separators; absolute paths, `.` and
`..` segments, empty segments, and Windows drive paths are rejected. Roots and
candidates are canonicalized before containment is checked. Symlinks are
allowed only when their final target remains below the canonical allowed root.
Only regular files are read, and reads are bounded to 4 MiB for source files
and 8 MiB for artifacts and diagram assets. Missing files remain a valid,
explicitly unavailable display state.

Producer-backed mode uses `--project-root` and `--mana-root`. The Explorer asks
that explicit Mana installation to materialize a Journey and validates the
returned JSON against the same contract.

## Failure behavior

Invalid JSON or malformed required fields produce a `Malformed Journey graph`
error. Missing or unsupported schemas produce a `Journey graph compatibility
error` that states the supported schema. The application presents these as a
controlled Journey-open failure and does not attempt partial rendering.

Missing source files, unavailable Git snapshots, and missing architecture
context are valid display states. They do not invalidate an otherwise
compatible graph and are surfaced without claiming unavailable evidence.
