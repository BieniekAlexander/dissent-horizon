---
title: Aerial operations
type: system-index
---

# Aerial operations

Everything an airframe does that a ground unit does not. Split out because it is the largest
single mechanic in the game and is almost never all needed at once.

| Note | Covers |
|---|---|
| [charged-ammunition.md](charged-ammunition.md) | clips refilled from outside, and the split-timer clamp that makes them work |
| [docking-bays-and-pads.md](docking-bays-and-pads.md) | `DockingBay`/`DockingPad`, landing on a deck, opting out, suspending flight |
| [runways.md](runways.md) | strips as lines, taxiing, takeoff rolls, approach and final |
| [attack-runs.md](attack-runs.md) | why a fixed wing never stops, dive attacks, the aim arc |
| [rearm-and-resupply.md](rearm-and-resupply.md) | the `Rearm` command, breaking off, resuming, and authoring |

**Reach for `tools/rearm_probe.gd` and `tools/attack_probe.gd` before changing anything here.**
The end-to-end flight has no GUT coverage; the probes are how it is actually observed.
