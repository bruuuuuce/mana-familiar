# Mana inspect compatibility

Mana owns the inspect contract and artifact semantics. Familiar supports the
Mana `mana-inspect-contract/v1` response schemas:

- `mana.inspect.project/v1`
- `mana.inspect.artifacts/v1`
- `mana.inspect.artifact/v1`
- `mana.inspect.source/v1`
- `mana.inspect.work-items/v1`
- `mana.inspect.work-item/v1`
- `mana.inspect.project-context/v1`
- `mana.inspect.activity/v1`

Before requesting optional detail or source relations, Familiar calls
`mana inspect project --json` and only invokes operations advertised in its
`operations` array with the exact supported schema. Unknown additive fields,
artifact families, relation types, statuses, and payload fields are retained
as raw data and otherwise safely ignored. An unknown schema is rejected; it is
never treated as a partially compatible v1 response.

Semantic mode is negotiated only from exact operation/schema pairs:

- FULL_SEMANTIC requires `work-items`, `work-item`, `project-context`, and
  `activity`;
- WORK_SEMANTIC requires both work operations but lacks at least one global
  semantic operation;
- LEGACY_CATALOG is selected when either work operation is unavailable.

An advertised operation that later fails produces a visible refresh warning.
Previously successful data for the same project and unchanged mode is retained;
it is never retained across a project or capability-mode change.

## Connection modes

1. **Project wrapper:** `--project-root <project>` uses that project's
   `./mana inspect … --json` wrapper when present.
2. **Explicit producer root:** when the project has no wrapper, provide both
   `--project-root <project>` and `--mana-root <mana>`; Familiar invokes the
   producer-owned `scripts/mana-inspect.sh` using structured process arguments.
3. **Saved response:** `--inspect-snapshot <response.json>` opens one saved,
   versioned inspect response without a Mana checkout. The response type must
   match the requested operation.
4. **Legacy Journey:** `--artifact <journey.json>` (or `--fixture`) remains
   the standalone `mana.learning.graph/v1` mode.

Transport failures, non-zero inspect exits, malformed JSON, unsupported
schemas, absent `.mana`, and partial catalogs remain distinct client states.
Familiar does not scan `.mana` as an offline fallback; saved inspect responses
are the offline fallback.

The process transport uses structured arguments without a shell, a 30-second
timeout, a 16 MiB response bound, bounded/redacted stderr, and explicit process
termination on timeout. Work-item IDs are validated before invocation. Typed
semantic responses reject unsafe `.mana` references, malformed ownership,
duplicate work/event IDs, duplicate sections/categories, and fake global
ownership.

## Artifact payload rendering

Artifact payloads are producer-owned and untrusted. Familiar dispatches through
an explicit renderer registry in this order: exact payload schema, known
artifact family/kind, content type, then metadata-only fallback. JSON, text,
and Markdown previews are bounded; Markdown is inert text with no link opening
or HTML execution. Unsupported, malformed, binary, oversized, deeply nested,
or future payloads remain visible as metadata rather than being interpreted.

## Markdown security policy

Reader mode uses native Flutter widgets, never a WebView. HTML, script, iframe,
embed, and object markup is inert and omitted from Reader mode. Link labels may
be rendered, but document-provided `javascript:`, `file:`, `data:`, relative,
and remote destinations are never opened. Remote images are not fetched.
Source and Metadata are selectable inert text and do not trigger filesystem or
network access. Only producer-declared source relations can request a source
operation, whose path must be safe, project-relative, and outside `.mana`.

### Operational renderers

When advertised in a payload, Familiar recognizes `mana.verification.result/v2`
and `mana.repair.bounded/v1`. Their fields remain producer-owned: a
verification result is evidence, never an approval; and bounded repair results
are limited to `RESOLVED`, `UNCHANGED`, `REGRESSED`, or `UNKNOWN`, where
`RESOLVED` is not a merge-ready decision. Activity uses only run/session,
timestamp, profile, workspace, status, and summary metadata actually supplied
by Mana. No action is executed from these views.

### Review, evidence, and governance

Structured payload renderers are limited to the documented schemas
`mana.review.findings/v1`, `mana.evidence.index/v1`, `mana.decision/v1`,
`mana.story-trace/v1`, and `mana.governance.report/v2`. Existing Mana review
and readiness Markdown remains safe text unless a versioned structured payload
is supplied; Familiar never derives findings from Markdown headings. Review
recommendations are advisory and human approval is displayed only when Mana
declares it. Every specialized view retains a bounded raw-payload section for
auditability.
