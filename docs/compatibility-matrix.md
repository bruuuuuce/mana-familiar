# Compatibility matrix

| Semantic mode | Required advertised operations | Available experience | Limitation |
| --- | --- | --- | --- |
| FULL_SEMANTIC | `work-items`, `work-item`, `project-context`, `activity` with exact v1 schemas | Overview, Work/dossier, Reviews, Knowledge, Activity, Advanced | Review/lifecycle/attention remain absent or unknown when Mana does not declare them. |
| WORK_SEMANTIC | `work-items` and `work-item`; project context or activity incomplete | Work/dossier and producer-owned review/work semantics; Advanced | Knowledge and Activity explain their unavailable capability instead of guessing. |
| LEGACY_CATALOG | Semantic work operations unavailable; catalog may remain | Explicit compatibility catalog, legacy Review/Knowledge adapters, Advanced | No semantic dossier/context/activity is fabricated from artifact names or paths. |

Transport can use a project-local `./mana` wrapper or an explicit compatible
`--mana-root`. A saved inspect response represents only its matching operation.
Direct `mana.learning.graph/v1` artifacts open the separate legacy Journey UI.

Familiar accepts the eight v1 inspect schemas listed in
[mana-inspect compatibility](mana-inspect-compatibility.md). Unknown additive
object fields are ignored safely; unknown enum values map to explicit unknown
state where the typed model supports it. Invalid identity, ownership, unsafe
paths, duplicate IDs, and unknown schema versions are rejected.

## Known limitations

- macOS desktop is the only supported runtime target.
- Familiar does not execute Review Inbox commands, approve work, repair a
  project, promote learning, or mutate `.mana`.
- A saved response cannot synthesize a multi-operation semantic session.
- The current inspect v1 contract exposes only explicit Journey-anchor source
  relations. Missing relation metadata is not treated as evidence of safety.
- Markdown links and images are inert. Familiar does not fetch remote images
  or open document-provided URLs; external editor opening is a separate,
  explicit user action using configured profiles.
- Inspect process cancellation is local; cancellation cannot undo work an
  incompatible external producer performed before termination. Compatible
  Mana v1 declares `writes:false` and is verified by C01/C02.
- Local preferences contain display settings, editor profiles, and a bounded
  list of recent project roots. They are not a credential store; do not put
  secrets in external-editor arguments or URI templates.
