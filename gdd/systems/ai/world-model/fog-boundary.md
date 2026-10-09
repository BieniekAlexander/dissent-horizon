---
title: The fog boundary
type: system-note
---

# The fog boundary

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## The fog boundary

A rule, and a check at the earliest stage where its inputs are fixed (`~/.claude/CLAUDE.md`
§5.4): **only L0 may call the fog-dependent scene queries, and no manager may read enemy
state from the scene at all.** The check is a `tests/test_SuiteIntegrity.gd`-style scan over
file text: a list of forbidden identifiers (`visible_enemies`, `get_enemies_near`,
`get_nodes_in_group("piece")`, `is_instance_valid` on a track's entity, …) that may appear
only in the perception files. A leak then fails CI rather than surviving as an honest
mistake.

The scan is `tests/test_BotFogBoundary.gd` (built 2026-10-06): every `bot_*.gd` manager file
is checked, comments stripped, for the omniscient calls — `get_enemies_near`,
`get_all_enemies`, `get_enemy_units`, `get_enemy_structures`, `nearest_enemy_structure_to_base`,
`get_nodes_in_group("piece")` — and any hit fails the suite. The fog-limited radius query a
sense may use is `Commander.visible_enemies_near`.

Three leaks were found by survey on 2026-10-06, before the scan existed, and FIXED the same
day (migration step 1):

1. `Commander.get_enemies_near` is a physics overlap with no visibility filter, and drove
   `is_base_under_threat`, `most_threatened_structure` and `threatened_command_centre` — the
   DEFEND posture, `BotEconomy.safety()` and defensive sanction aiming. Those three senses,
   `BotSanction` and `BotTargeting` now read `visible_enemies_near`; `get_enemies_near` is
   documented as the omniscient primitive under `visible_enemies()` and nothing above
   perception calls it.
2. `believed_enemy_army_value` and `enemy_demand_map` dropped entries whose entity failed
   `is_instance_valid`, so an enemy that died out of sight left the estimate instantly. Every
   belief now counts; the demand map's live `rep` is borrowed as a type-level stat carrier
   (`Bot._any_instance_of_type`), null for an extinct type, with a `TODO` that type-level
   effectiveness removes it.
3. `BotMilitary._objective_is_standing` read the remembered objective's liveness. It now asks
   `CommanderBlackboard.believes(instance_id)` — a structure stands until the bot SEES its
   cell empty — and the node's validity is checked only at the Attack order, an actuation
   necessity that changes no decision. `Bot.belief_is_disproved` read a remembered unit's
   live position whatever its visibility, so a stealthed unit on the spot read as "still
   there"; the position is now read only for a piece the bot can see.

**A death the bot watched is evidence; one it did not is not** (Alex, 2026-10-07). An enemy
unit in view at the blackboard's last update that has died since is dropped at once —
`CommanderBlackboard.update` reads liveness only for a unit it was watching. A unit that died
out of sight is believed for the full expiry window, as before; one seen gone from its spot
is believed too, since it may have walked on. Before this, every enemy the bot killed in
front of itself counted toward the army it believed it faced for three minutes more:
measured in a Recruit-heavy match at two to four times the real army, which kept the bot
from ever feeling far enough ahead to attack. The rest of negative evidence is still step 2
of §Migration.
