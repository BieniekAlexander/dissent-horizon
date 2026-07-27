---
title: Auditing the design — where a concept applies, and where it does not
type: design-note
---

# Auditing the design

The question this answers: *where does "intercepting a commitment" (or reversal, or grappler)
appear in the game as planned — per faction, and at what point in a match?*

**Recommendation: a closed vocabulary of design roles, declared per piece in its spec doc, with
the cross-tabs generated rather than maintained.** Not a free-form knowledge graph.

## Why not a knowledge graph

A graph of links — Obsidian's included — records that two notes are connected, not *how*. A wiki
link from a piece to a concept note is the same edge whether the piece **is** an instance of the
concept, **counters** it, or merely mentions it in passing. Querying that graph answers "what
talks about reversal", when the audit needs "what IS one, whose, and how early". The relation
being asked about is typed, directional and countable, which is a **property on the piece**, not
an edge in a mention graph.

## The three parts

**1. A closed role vocabulary.** Roughly the concept index in [README](README.md) — a dozen or so
entries, deliberately closed, because the audit only means something if two pieces claiming
`reversal` mean the same thing by it. Each role gets a note saying what it is, what a good
instance looks like, and which rules it must satisfy.

This vault already has the beginnings of exactly this: `gdd/games/` holds a note per concept —
footsies, siege, stealth, garrison, timers, interception, delivery — several already carrying
per-faction weights in their frontmatter. That is the registry in proto form, hand-weighted.
**Fold it in rather than inventing a parallel scheme.**

**2. Per-piece declarations.** `roles: [reversal, zoning]` in the spec doc's frontmatter, authored
beside the piece it describes. This follows the project's data rule: the human-authorable doc is
the source, and everything else derives from it.

Author the role, never infer it. A piece can be a reversal by virtue of its reach and cooldown
with no ability attached at all — the Bombard is — so a component scan would miss precisely the
interesting cases.

**3. Generated cross-tabs.** Role × faction, and role × earliest availability. Nothing
hand-maintained: a table of this kind is wrong within a month of being written.

## The timeline comes from the tech tree

A piece's earliest availability is already computable from the `requires` chains that produce the
faction tech graphs, so every (piece, role) pair carries a depth for free. That turns design
intentions into checks:

- **"Every faction should have some defensive reversal."** The role appears at least once per
  faction — and the sharper form, which the counting cannot give you: each instance states what
  it answers and what it does not. A Bombard covers slow ground pushes and not nimble or airborne
  ones, and that sentence is the actual audit result.
- **"Volatile roles do not belong at the very start of a match."** Minimum depth for `read` and
  `grappler` is at or above a threshold, per faction.
- **"This faction is built around punishing mistakes."** The faction doc names the roles meant to
  be *central* to it, so intent is recorded and can be compared against what the roster actually
  offers. A faction claiming the grappler fantasy with its only grappler at maximum tech depth is
  the kind of inconsistency this is for.

## Two views, nearly free

**Inside Obsidian**, Dataview over frontmatter gives both directions with no tooling: the concept
note lists every piece claiming that role, and the faction doc lists the roles it covers and how
deep each one is. The vault already runs `dataviewjs` for the tech graphs, so it is the same
machinery.

**Outside Obsidian**, the spec importer already parses and validates every doc's frontmatter, so
an unknown role id can be a hard validation error, and the same pass can emit the cross-tab as a
generated artifact — the way the technology and tool data are generated today. Generated,
ignored by git, regenerated, never hand-edited.

## What it cannot do

A role tag is a **claim**, not a measurement — **accepted deliberately**, because these
properties are too difficult to measure explicitly. Nothing checks that a piece tagged `reversal` plays
like one; the tag is only as good as the vocabulary's definitions. So the audit finds **absences
and inconsistencies** reliably, and presence only as an assertion to review — which is the right
division of labour, because absence is the thing that is genuinely hard to notice by reading.

Keep roles per piece rather than per weapon, and expect two or three at most. A piece needing
five is either doing too much, or the vocabulary has been cut too fine.

## Work order, if adopted

1. Close the vocabulary; fold `gdd/games/` in as the concept notes.
2. Add `roles:` to the spec schema; the importer validates against the vocabulary.
3. Dataview views in the concept notes and the faction docs.
4. A generated cross-tab — role × faction × earliest depth — plus the rule checks above.

TODO: define "depth" before generating anything. Structures in the prerequisite chain is the
obvious measure and ignores cost and build time, which are what actually decide when a thing can
be on the field.
