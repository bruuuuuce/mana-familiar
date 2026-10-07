# Knowledge workspace

Familiar presents the existing Mana Knowledge contracts through four views:

- **Home** offers reading history, a library preview, declared project categories,
  and learning proposals. Reading history is bounded to eight documents per
  project and twenty projects in Familiar preferences. It stores document metadata,
  never document bodies, and reopening a recent source asks Mana for its current version.
- **Library** supports project, user, framework, and combined source filters,
  lifecycle filters, and additional pages. Pages from a different index revision
  are rejected rather than combined with the current library.
- **Learning** displays proposals, evidence, counter-evidence, and limitations.
  Review and promotion use the existing revision-checked actions and remain separate.
- **Journeys** opens the existing Journey picker and reader only when selected.

Search results preserve producer passage identities, heading paths, and revisions.
Opening a result highlights and scrolls to that passage. If the document preview
omits or truncates the passage, Familiar requests it through `knowledge passage`
at the same index revision. Late document and pagination responses cannot replace
a newer selection, source filter, or refresh.

The reader reuses Familiar's Markdown renderer and adds a section outline and
expandable provenance. Exact source is shown only when Mana supplies it; otherwise
Source mode explicitly identifies the passage excerpt. Section links navigate
within the loaded preview. Relative document links open matching producer-owned
documents in the loaded library; unavailable targets direct the user to search
or pagination. HTTP(S) links can be copied, without fetching remote content.

Mana remains responsible for indexing, retrieval, authority, and mutations.
This change adds no inferred knowledge relationships or new Mana contracts.

## Journey reading

Journeys now open in **Read**, with **Source** and **Graph** available as separate
views. Read brings existing explanations, epistemic status, linked evidence,
bounded source excerpts, hypotheses/checks, and primary continuation rationale
into one scrollable surface. Deferred and alternative branches remain optional.
Failed explanations are excluded from reading content and coverage counts.
Learning objectives and prerequisites are explicitly unavailable in the current
producer format; Familiar does not fabricate them from graph labels.

The picker reports known steps, explanation coverage, and the last reading point.
Reading markers (`Read`, `Clear to me`, `Needs review`) are explicit personal
choices. Opening a node updates the resume point without marking it read.
A summary filters all steps, points needing review, or steps with notes, and
opens the selected step. A branch ending is never presented as verified learning.

Preferences store local Journey IDs, last node, markers, user-authored notes,
and a deterministic change detector. They store no source or explanation bodies.
History retains at most twenty projects, thirty Journeys per project, two thousand
markers and two hundred notes per Journey; notes are limited to four thousand
characters. Reopening reconciles saved identities with the current materialization.
Removed steps cannot be resumed. Materialization changes retain valid notes and
turn prior markers into `Needs review`. Dismissing the change notice does not
restore previous clarity markers. Late hydration from a previous materialization
cannot replace the current source, labels, or reading state.

The Journey reading work changes only Familiar. Mana's Journey records, source
snapshots, and learning-candidate lifecycle remain producer-owned. A teaching
model with authored goals, questions, and evidence-backed conclusions needs a
separate Mana contract.
