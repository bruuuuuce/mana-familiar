# Consumer architecture

Mana Familiar is a read-only desktop consumer of Mana inspect contracts. It
owns presentation, semantic route state, safe document rendering, source
viewing, and local UI preferences. Mana owns work-item identity and lifecycle,
attention, review state, section/category mapping, activity chronology,
artifact relations, diagnostics, and coverage.

## Application structure

`main.dart` is the composition root only: it initializes Flutter, parses
startup arguments, loads local preferences, and starts the app. The remaining
responsibilities are deliberately located by their role:

- `app/mana_familiar_app.dart` composes Material theme and the top-level page;
- `application/explorer_config.dart` owns immutable command-line and
  auto-discovered roots;
- `application/mana_inspect.dart` is the typed, read-only transport boundary
  for all eight Mana-owned inspect v1 responses and saved snapshots; it uses
  structured process arguments, bounded output, a timeout, refresh coalescing,
  and last-successful-data retention, and it does not scan `.mana`;
- `application/semantic_navigation.dart` owns the complete semantic route and
  back/forward state;
- `presentation/project_observatory_page.dart` lazily loads artifact details,
  suppresses stale async responses, and presents Overview, Work, Reviews,
  Knowledge, Activity, and Advanced without semantic inference;
- `presentation/artifact_detail_view.dart` is the native, inert Markdown
  Reader/Source/Metadata surface;
- `presentation/explorer_page.dart` owns the explicitly separate legacy
  Journey screen and its screen-local state;
- root-level focused modules own Journey graph logic, navigation, source
  resolution, architecture context, diagrams, investigation, and editor
  integration.

The public types historically imported from `main.dart` remain re-exported
there for test and embedding compatibility. This reorganization changes no
artifact contract, loading mode, or UI behavior.

## Semantic producer boundary

Given `--project-root`, the Observatory invokes only operations advertised by
`mana.inspect.project/v1` with their exact accepted schemas:

```text
project → artifacts → artifact/source
        → work-items → work-item
        → project-context
        → activity
```

All subprocess arguments are passed as distinct values with `runInShell:false`.
The default transport has a 30-second timeout, retains at most 16 MiB stdout
and 8 KiB stderr, terminates timed-out processes, and redacts/bounds failure
messages. One semantic refresh negotiates once and invokes each advertised list
operation at most once; concurrent refresh requests share that future.

Familiar never derives chronology, ownership, sections, project categories,
review state, lifecycle, or attention from paths, filenames, prose, or legacy
families in FULL_SEMANTIC or WORK_SEMANTIC.

## Explicit legacy boundary

The standalone `mana.learning.graph/v1` Journey explorer and LEGACY_CATALOG
views remain compatibility paths. Their path/family classification cannot be
called by FULL_SEMANTIC or WORK_SEMANTIC routing. Direct-artifact source and
diagram files are read only after canonical containment, regular-file,
symlink, and size validation.

## Ownership and persistence

The Observatory never parses or writes individual `.mana` files. User
interface preferences are stored outside the project in macOS Application
Support or the platform configuration directory. They are deliberately not
Mana artifacts. Application-local caches are bounded to the process and are
invalidated/reconciled by semantic refresh.

Mana Familiar pins its accepted consumer contract locally in
[`artifact-compatibility.md`](artifact-compatibility.md). Changes to the
materialized graph or the CLI commands above require a compatible producer
release and a corresponding Mana Familiar update. The app rejects missing or
unsupported graph schema identifiers before rendering.
