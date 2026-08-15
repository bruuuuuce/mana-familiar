# Product boundary

Mana Familiar is a **read-only**, human-facing desktop client. It renders
versioned contracts owned by Mana; it does not create, edit, repair, or
reinterpret Mana records and it never writes source code or Journey artifacts.

Mana owns semantics, governance, artifact discovery, validation, and stable
read contracts. Familiar owns presentation, navigation, source and diagram
viewing, and local UI preferences. Artifact data and paths are untrusted: the
client accepts only its documented schema and reads artifact-relative assets
only after containment, regular-file, symlink, and size checks.

The current product is the project observatory. FULL_SEMANTIC exposes Overview,
Work, Reviews, the eight producer-owned Knowledge categories, Activity, and
Advanced. Knowledge and dossier documents remain in their typed semantic
parent and render through the inert native reader. The product does not add a
competing generic `.mana` parser, knowledge database, or write surface.

Reviews in semantic modes derives only from typed work-item review, attention,
ownership, and review-section references. Unknown review state remains sparse.
Legacy catalog ReviewInboxModel and KnowledgeModulePage classification is
retained solely for LEGACY_CATALOG compatibility and cannot affect semantic
routes. Missing action metadata remains unavailable rather than guessed.
