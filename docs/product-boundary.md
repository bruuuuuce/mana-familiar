# Product boundary

Mana Familiar is a **read-first**, human-facing desktop client. It renders
versioned contracts owned by Mana and never reinterprets records or writes
source code or Journey artifacts. The only write surfaces are explicit,
capability-advertised Mana actions for revision-checked Project Knowledge,
explicitly disclosed external User Context Knowledge, Learning
dispositions/promotion, and scheduler retry/cancel. Familiar never edits the
generated User Context mirror: the confirmation shows the external root, exact
content, and revision before Mana performs and receipts the mutation.

Mana owns semantics, governance, artifact discovery, validation, and stable
read contracts. Familiar owns presentation, navigation, source and diagram
viewing, and local UI preferences. Artifact data and paths are untrusted: the
client accepts only its documented schema and reads artifact-relative assets
only after containment, regular-file, symlink, and size checks.

The current product is the project observatory. FULL_SEMANTIC exposes Overview,
Work, Reviews, the eight producer-owned Knowledge categories, Activity, and
Advanced. The M08 Knowledge Center uses the separate published Knowledge
contracts for scoped search, document detail, and the Learning queue. Knowledge
and dossier documents remain in their typed semantic parent and render through
the inert native reader. The product does not add a competing generic `.mana`
parser or knowledge database.

Accepting a User Learning candidate never promotes it. Familiar exposes
promotion only as a second action when Mana supplies the exact approved review
identity and revision.

Reviews in semantic modes derives only from typed work-item review, attention,
ownership, and review-section references. Unknown review state remains sparse.
Legacy catalog ReviewInboxModel and KnowledgeModulePage classification is
retained solely for LEGACY_CATALOG compatibility and cannot affect semantic
routes. Missing action metadata remains unavailable rather than guessed.

The PR Inbox reads host-owned scheduler state and may request retry or cancel.
Familiar is never the scheduler host, never stores GitHub credentials, never
runs the review provider directly, and exposes publication as unavailable until
Mana advertises an explicit current-revision publication boundary.
