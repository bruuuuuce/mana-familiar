# Compatibility matrix

| Mode | Required producer contract | Available experience | Limitation |
| --- | --- | --- | --- |
| Project wrapper | `./mana inspect` v1 | Observatory, artifact/source relations, Knowledge and Review Inbox | Requires the project wrapper and a usable `.mana` workspace. |
| Explicit Mana root | inspect v1 scripts under `--mana-root` | Same inspect-based observatory experience | The selected Mana root must be compatible; Familiar does not discover arbitrary producers. |
| Saved inspect response | One matching v1 response | Read-only catalog/demo view | A saved response represents one operation; unavailable details and sources stay unavailable. |
| Direct Journey artifact | `mana.learning.graph/v1` | Legacy Journey source, graph, diagram and investigation view | It is intentionally separate from the inspect project observatory. |

Familiar accepts the four v1 inspect schemas listed in
[mana-inspect compatibility](mana-inspect-compatibility.md). Unknown additive
artifact fields and kinds retain their safe fallback summary; unknown schema
versions are rejected rather than guessed.

## Known limitations

- macOS desktop is the only supported runtime target.
- Familiar does not execute Review Inbox commands, approve work, repair a
  project, promote learning, or mutate `.mana`.
- The current inspect v1 contract exposes only explicit Journey-anchor source
  relations. Missing relation metadata is not treated as evidence of safety.
- Local preferences contain display settings, editor profiles, and a bounded
  list of recent project roots. They are not a credential store; do not put
  secrets in external-editor arguments or URI templates.
