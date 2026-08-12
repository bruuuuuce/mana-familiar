# Product boundary

Mana Familiar is a **read-only**, human-facing desktop client. It renders
versioned contracts owned by Mana; it does not create, edit, repair, or
reinterpret Mana records and it never writes source code or Journey artifacts.

Mana owns semantics, governance, artifact discovery, validation, and stable
read contracts. Familiar owns presentation, navigation, source and diagram
viewing, and local UI preferences. Artifact data and paths are untrusted: the
client accepts only its documented schema and reads artifact-relative assets
only after containment, regular-file, symlink, and size checks.

The current product is the Learning Journey explorer for
`mana.learning.graph/v1`. It will broaden into a project observatory only
through a versioned Mana-owned inspect contract. It will not add a competing
generic `.mana` parser or a write surface while making that transition.
