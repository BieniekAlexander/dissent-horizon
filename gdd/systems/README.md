---
title: Systems design notes
type: system-index
---

# Systems design notes

The mechanics of Dissent Horizon, written up as rules with their reasoning. `CLAUDE.md`
carries the project-wide invariants and a pointer to each system; **the detail lives here**,
so it costs nothing until someone is actually working on that system.

## The six systems

| System | Covers |
|---|---|
| [Terrain and Navigation](terrain-and-navigation/) | the ground itself, and how things move over it |
| [Combat](combat/) | how entities hurt, hold and destroy each other |
| [Commands](commands/) | issuing, queueing and carrying out orders |
| [Macroeconomics](macroeconomics/) | resources, production, technology and unlock trees |
| [UX](ux/) | what the player sees, hears and touches: the interface (`ui/`) and the aesthetics it is judged by |
| [Scenario scripting](scenario-scripting/) | authored missions: triggers, objectives, dialogs |
| [Authoring](authoring/) | the gdd-doc → scene pipeline, and code-level audits |

The last two sit outside the five headline systems deliberately. Scenario scripting is a
mission-authoring language rather than a game mechanic, and Authoring is the tooling that
turns these docs into scenes — neither belongs under a gameplay heading.

## Filing rule

**A new mechanic's write-up goes in the note for its system. `CLAUDE.md` gets the pointer,
never the write-up.** That is what keeps per-session context small.

1. Find the system it belongs to. Each folder's `README.md` states its scope boundary — read
   that, don't guess from the folder name.
2. Add it to the existing note that already covers the nearest thing. A new note is for a
   mechanic with no existing home, not for every new rule.
3. A note past roughly 12 KB wants splitting. Split at its `##` boundaries into a
   subfolder with its own `README.md`, the way `combat/aerial-operations/` is split.
4. If it genuinely spans two systems, file it under the one whose code owns it and
   cross-link from the other. Do not write it twice.

## What does NOT belong here

- **Piece stats** — those are spec docs (`gdd/factions/**`), governed by the importer.
  A note here may cite a piece; it must not restate its numbers.
- **Anything with a `kind:` frontmatter key.** Discovery is by that key, so a `kind:` here
  would make the spec importer try to import a prose note. These notes use
  `type: system-note` instead.
- **Task state** — that is `gdd/tasks.md`, a queue rather than a record.
- **Changelogs.** Git already records what changed and when. A note states what is true now,
  with the superseded design named only where knowing it prevents a repeat mistake.
