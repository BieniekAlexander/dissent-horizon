---
title: Aesthetics
type: system-index
---

# Aesthetics

How the game's assets are JUDGED, as distinct from whether they exist. Presence is binary and
tracked as a slot kind in [../README.md](../README.md); a question with a better or worse
answer — does this silhouette say "unarmed"? — lives here, keyed to the same slot kinds.

**The test for every addition:** does it make the game more readable, more satisfying to
command, or more distinctively part of this world? If it does none of those, it is a
lower-priority asset.

| Note | Covers |
|---|---|
| [art-direction.md](art-direction.md) | the high-level aesthetic goals: pillars, tone, rendering style, technology level, cultural anchors |
| [lighting.md](lighting.md) | the default lighting rig and Environment, the research behind them, options not taken |
| [terrain-readability.md](terrain-readability.md) | how the terrain shader shows height and passability |

## Considerations, by slot kind

A consideration that a program can check becomes an audit rule (`tools/ui_audit.gd` already
measures models against their selection shapes and HP bars). The rest stay a review list.

### Models

- **Silhouette first, effects second, detail third.** A unit that cannot be recognised at
  normal camera distance without particles or UI labels needs a stronger model.
- **Role reads before the tooltip does.** The damage model runs on frame (bio/mech) and
  armour class (light/medium/strong), so those are what a silhouette must separate first;
  after that come speed, reach, and whether the piece is armed at all.
- **Scale cues ground a piece:** a footprint, shadow, dust, exhaust, recoil.

### Condition and effect visuals

- **The telegraph rule is a visual requirement.** Any effect above a payoff threshold needs a
  visible pre-state that lasts long enough for a player looking elsewhere to catch it
  ([ideas.md](../../../design-framework/ideas.md) §The telegraph rule).
- **Only what a player must know is visualised.** Emergent dynamics such as overkill are
  deliberately left for players to discover ([design-framework](../../../design-framework/README.md)
  §Settled).

### Emission visuals

- A visual that shows direction of travel (a trail, a tracer) earns its place wherever the
  direction is what the target has to react to. Whether a given phase needs one is decided
  here; whether the decision has been recorded is the slot's `EXEMPT` state.

### Audio

For every audio event, state what triggers it, how urgent it is, whether it can repeat, what
happens when many instances overlap, and how it changes with distance or zoom. Player
commands and alerts take mix priority; repeated voice lines are capped.

## Art direction

The goals are set in [art-direction.md](art-direction.md); what follows is the work still open under them.

TODO: undecided — a shape language, palette and material set per faction, drawn from
[world-building.md](../../../world-building.md): Haustorian imperial expansion, Tselerate
brutalism, Baladian scavenged kit, opaque Ward machines, Successor biorobotics. Each
faction's roles share a function and differ in appearance.

TODO: undecided — biomes. The setting is planetary, and one desert map exists; there is no
biome concept in the terrain model yet.

TODO: a proposed order, not adopted — art direction and UI language first; then a
vertical slice (one biome, one faction, its core pieces, HUD, combat audio); then the full
roster and its states; then menus, campaign and variety; then a clarity pass at gameplay zoom
covering clutter, alerts and accessibility.
