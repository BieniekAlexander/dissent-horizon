# Challenge 1 — Controls

Status: draft. Drills the control idioms that differ from RTS convention: how many actors an order goes to, the selector keys, and control groups.

## Skill

- **Modifier controls.** Shift appends, which is conventional. Alt narrows and Ctrl broadens, which is not:
  - On an order, Alt sends it to one actor and Ctrl to all selected actors.
  - On a selector, Alt restricts to idle members and Ctrl takes all members.
  - This is the idiom veterans of other RTS games will misread, so it gets the most drilling.
- **The F1–F3 selector matrix:** builders, army and production, and how the modifiers change what a selector picks up.
- **Control groups:** setting, recalling, adding to and removing from a group.

The bindings and every cell's meaning are in [control-matrices](../../systems/ux/ui/control-matrices.md) (Context 4 for selectors, Context 10 for control groups) and [selection-and-input](../../systems/ux/ui/selection-and-input.md). This doc names the drills, not the keys.

## Prerequisites

Prologue mission 1 (basic selection and orders).

## Drills

- **Assignment:**
  - A group of builders and several build sites. Sending all of them to one site is the default, and sending one to each site is the narrow case. Score on how fast every site is started.
  - The reverse case uses an order whose default is narrow.
- **Selectors:**
  - Idle builders scattered around a base. Pull exactly the idle ones without box-selecting.
  - Then every production structure at once, to queue units across all of them.
- **Control groups:** a fight on two fronts at once, where each front needs its own group. Set the groups, recall them as fights flare, and move a unit from one group to another mid-fight.
- **Combined test:** a timed scenario needing all three: pull idle builders onto new sites, regroup the army across two fronts, and queue reinforcements from every producer.

## Pass and score

- **Pass:** complete the combined test within its time limit.
- **Score:** time taken, plus the number of orders issued (fewer is better, rewarding the right modifier over repeated clicks).

## Pieces

- [Irregulars](../../factions/anarchical/units/an_bioLight_builder.md) as builders
- Anarchist production structures
- A mixed army
- Colonial attackers for the two-front drill

## Scenario file

TODO — link once it exists under `scenes/scenarios/`.

## Open questions

- Does the challenge show the modifier being held on screen, as a teaching aid?
- How does it handle macOS, where broaden and narrow move to Option and Command? On-screen prompts should come from the bindings (`InputPrompt`), not hardcoded key names.
- Control groups have no HUD yet (the group panel is deliberately unbuilt). Is a challenge about them playable before that panel exists?
