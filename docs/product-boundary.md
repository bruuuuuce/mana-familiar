# Product boundary

Mana Familiar is a **read-only**, human-facing desktop client. It renders
versioned contracts owned by Mana; it does not create, edit, repair, or
reinterpret Mana records and it never writes source code or Journey artifacts.

Mana owns semantics, governance, artifact discovery, validation, and stable
read contracts. Familiar owns presentation, navigation, source and diagram
viewing, and local UI preferences. Artifact data and paths are untrusted: the
client accepts only its documented schema and reads artifact-relative assets
only after containment, regular-file, symlink, and size checks.

The current product is the project observatory. Its Knowledge module preserves
the Learning Journey explorer for `mana.learning.graph/v1` under
**Knowledge > Journeys** and exposes other Knowledge categories only when
Mana's versioned inspect catalog reports matching artifacts. It does not add a
competing generic `.mana` parser, knowledge database, or write surface.
