---
title: Sanction grid
type: system-note
---

# Sanction grid

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*


> **The word, and which sense it carries.** *Sanction* here is always the VERB's sense — **to
> authorise, to permit** — never the punitive plural. A sanction is your broader faction
> signing off on something you may then do, which is why the resource that buys one is
> DOMINION: dominion is control over territory, and authority follows from it. The contronym
> is unfortunate and was accepted with open eyes; if you find yourself reading "the Colonial
> sanctions" as a blockade, read it as a commission instead.

**"Sanction" means exactly one thing: an ability unlocked with the DOMINION resource, through this grid.** It is an unlock ROUTE, not a kind of thing — what a cell grants is an ABILITY, and abilities also arrive for free (the Bombard's battery — owning the gun is the unlock) or bought at a structure through the ordinary purchase queue. Nothing about an ability changes with the route it took: it still lives in an `Abilities` pool on the piece that uses it, and it is still defined by a `kind: AbilityDefinition` doc. What the route decides is who may buy it and what it costs.

A sanction grants either an ACTIVE ability (Scan, Ambush) or a PASSIVE one (Scavenge). A commander-level sanction is unlocked with dominion, then aimed at a map position. The set a faction offers is a **GRID** — `SanctionGrid.NUM_TIERS` rows by `NUM_COLUMNS` columns, one `SanctionUnlock` per cell — and the two axes carry two different rules. Keeping them separate is the whole design. Two grids are authored — the tables in `gdd/factions/colonial/colonial.md` (12 cells) and `gdd/factions/anarchical/anarchical.md` (13) — TODO: both used to be pinned cell by cell in `tests/test_FactionRosters.gd`; that test was cut as an authored-content test (CLAUDE.md §A unit test does not assert facts about authored content). **Nothing now catches a `.tscn` edit drifting from the table**, and the table IS the design — if that drift matters, it wants a check that reads the doc rather than one that hard-codes the cells.

| Axis | Means | Rule |
| --- | --- | --- |
| **row** = `tier` | how deep into the sanction grid you are; the last row is the superweapon tier | tier 0 is open from the start; every other tier opens once `UNLOCKS_TO_OPEN_NEXT_TIER` (2) cells in the tier ABOVE are owned — **whichever** two |
| **column** = `parent` chain | one FAMILY of sanctions (every Scan, every Freeze) | a cell's `parent` is the cell it continues; it must be owned first, must sit in a strictly lower tier, and must share the column |

**Depth costs breadth, and that is the point of having two axes.** The tier gate counts unlocks without caring which, so it can never be satisfied by rushing one family — you have to buy across the sanction grid to get down it. A single edge list cannot say this: `prerequisites: Array[SanctionUnlock]` with any-of semantics was what this replaced, and it expressed breadth only by pointing every deep node at every shallow one, left a genuine chain indistinguishable from a fan-in, and had no way at all to say which unlock an upgrade upgrades.

**A parent need not sit in the tier directly above.** The Anarchists' Informant 3 is two tiers below Informant 2. (Blizzard, two tiers below Freeze 2, shares the Freeze column without continuing it.) Non-adjacency is what makes the tier rule bite — continuing a family late still means paying the breadth toll to get down there.

**Sharing a column does NOT imply an edge.** Gunship sits under Scan 2 in the same column with no parent; it is in the scan family's column because that is where it belongs on screen, not because it continues it.

**An unlock SUPERSEDES a LOWER LEVEL OF THE SAME ABILITY** (`SanctionGrid.is_superseded`, off `effective_level`). Freeze 2 replaces Freeze 1 in the deployable set rather than joining it, so a column is one sanction the player improves and the deploy bar stays at roughly one button per family however deep they go. Two consequences worth knowing:

- A superseded cell is **still owned**. It keeps paying its share of the tier toll, so upgrading a family can never shut a tier it had already opened. `is_deployable` is the narrower question, and `deployable_sanctions()` is what every consumer reads — the bar, the bot, cooldown ticking — so nothing can leave a superseded sanction in play.
- Supersession is DERIVED from what is owned — the highest unlocked `Sanction.ability_level` for an `ability_id` wins — so there is one fact and no second flag to keep in step with it.

**It used to be read off the parent chain, and that mechanism is retired.** A cell has one `parent`, so the chain could only ever say "this cell replaces that one" — and the Colonial Drop family needs a cell that grants a NEW ability *and* upgrades an existing one at the same time (Drop 2 grants `drop2` and raises `drop1` to level 2). Levels say the same thing about the simple case and can also say that. `parent` survives, but only as the UNLOCK GATE — "you must own that cell before you may buy this one" — which is a different question from which level is in play. Tests: `test_a_cell_can_raise_an_ability_it_does_not_sit_under`.

**Authoring faults are reported when the sanction grid is BUILT**, in `SanctionGrid._slot_is_usable` / `_report_authoring_faults`, because every one of them is otherwise silent — the sanction simply never becomes available, which looks like a balance decision. Two cells claiming one slot, a slot outside the grid, a parent that is not in the faction's `sanction_unlocks`, a parent at or below its child's tier, a parent in another column, and a tier whose predecessor holds fewer than two cells (so it can never open) are each named with the offending sanction. Tests: `tests/test_SanctionGrid.gd`.

## The fog gate is the default, and a scan opts out


`Sanction.can_target` refuses a target the commander does not have **live** vision of — explored-once is not enough, so a strike cannot be called down blind into the shroud. That is scouting's whole job, which is why the gate is stated as a default a sanction opts OUT of (`Sanction.needs_vision`, **true**) rather than one it opts into: an un-authored sanction is fog-gated, and forgetting the flag costs a little reach rather than silently repealing scouting.

**False is for the sanctions whose job IS to see.** The Colonials' whole Scan family sets it, because a reveal you may only aim at ground you can already see is useful precisely where it is not needed. It is set on both cells rather than only the first: a column is one sanction the player improves (see supersession above), so Scan 2 inheriting the gate would re-break the thing at the exact moment the player paid to make it better.

Two things keep it honest:

- **`can_target` is an INSTANCE method**, not the static it used to be — the answer now depends on which sanction is being dropped, not on the position alone. Callers that read it statically would have compiled against the old rule and silently kept the gate.
- **The gate stays inside `activate`**, the single choke point every deployment path goes through (the player's click, the bot, a scripted event). Waiving vision waives *only* vision: readiness, cost and cooldown are untouched, so a scan cannot be spammed.

Tests: `tests/test_SanctionTargeting.gd`, which pins the default, both halves of the opt-out (predicate and deployment path), that the flag survives the per-commander `duplicate()`, and that the Colonial scans opted out while their sanction grid siblings did not.

## Unlocking and deploying are two HUD surfaces


Split because the two are asked at completely different moments, and one bar trying to be both is what the filled-out Colonial grid (14 cells) made untenable:

| | Where | Shows | Does |
| --- | --- | --- | --- |
| **deploy bar** | top of the screen, always up | one button per ABILITY that authors `hud_button: true` and has somewhere to be used from | click to arm, then click the map to aim |
| **unlock menu** | centred card, toggled by the bar's `Sanctions` button | the whole grid, locked cells included | click to spend dominion |

**The bar is not a sanction grid surface, and that decoupling is deliberate.** A button used to appear iff the ability was dominion-unlocked and deployable, which conflated the shop with the HUD: a global-range ability nobody paid dominion for — the Bombard's battery — could not have one. HUD presence is now AUTHORED, `hud_button:` on the ability doc, defaulting to false, and the rule of thumb for setting it is REACH: an ability whose effective range is global wants a button, because the player cannot walk the map to find a caster. Being dominion-unlocked is now only an extra visibility gate on top — such a button also waits for a cell of that ability to be in play.

The bar's buttons are built once per ABILITY and SHOWN when the commander can actually use one — the set never changes during a match, so a rebuild has nothing to discover. A dominion-unlocked ability's button follows whichever LEVEL is in play, and rebuilds its copy only when that changes. Pressing any of them selects every piece that can use the ability and arms it, leaving one right-click to aim — the bar is a shortcut to an order, never a second caster. Opening the menu drops any armed sanction: it is a planning surface, and a right-click made over it should not fire something armed beforehand.

Every locked cell in the menu **names what is missing** ("needs Freeze 1", "1 more in T1") rather than reading "locked", because the remedies differ: buy the parent, buy anything in the tier above, or wait for dominion. The menu is laid out by a full-rect root → `CenterContainer` → `PanelContainer`, **not** by arithmetic: a `PanelContainer` added straight to the `RTSController` CanvasLayer has no layout parent, takes the whole screen height, and then has to be positioned by hand — which put it underneath the deploy bar. Only the panel joins `selection_blocking_ui`; a full-screen blocker would make the world unclickable while the sanction grid is up. That bug was found by rendering the panel offscreen (§Seeing the HUD without a screen) via `tools/sanction_menu_preview.tscn`, which is the only way to reach these states without minutes of play.

## What a faction offers IS its grid

An ordnance the faction cannot reach at all is **not on the ORDNANCE card**, as against
being on it and drawn dark. Dark means "you could work toward this"; absent means "not for
you". `SanctionGrid.has_route_to` answers the first question — does the faction's grid hold
any cell granting this ability, owned or not — and it is a different question from
`deployable_entry_for`'s "can this commander use it right now".

It is derived from the faction's own authored unlock grid rather than from a faction TAG on
the ability, so the two cannot disagree.

## Authoring a sanction grid


**The grid's SHAPE is authored in the gdd docs; only the PAYLOAD lives in the scene.** A faction's `sanctions:` list names `kind: AbilityDefinition` docs that author a dominion route (`gdd/factions/*/sanctions/*.md`), one per FAMILY, and the importer rebuilds `Faction.sanction_unlocks` from them — tier, column, parent chain, cost, cooldown, both tiers of copy, and the behaviour flags. **A cell added to the scene and not to a doc is deleted by the next import.**

| In the doc | In the scene |
| --- | --- |
| `column`, per-level `tier`, level ORDER (the parent chain) | `Sanction.event_scene` — the payload |
| `cost`, `cooldown`, `description`, `verbose` | `targeting`, `effect_radius`, `min_targets` (the bot's aiming knobs) |
| `needs_vision`, `needs_target`, `kill_bounty` (per level) | |
| `passive`, `hud_button` — the ability's own, at the doc's TOP level | |

A doc is one FAMILY — a chain down one column, each level superseding the one above it — so **`parent` is never authored by hand: it IS the level ordering**, and a level must sit strictly lower in the grid than the one before it. A family is not the same thing as a column: unrelated sanctions sharing a column (Gunship under Scan 2, Global EMP under Scavenge 3) are separate docs carrying the same `column`, which is exactly the "sharing a column does NOT imply an edge" rule made structural.

The split is where it is because a sanction's behaviour is an EVENT SCENE, which is not a value anyone can type into YAML. So the doc carries the numbers and the prose, and the doc BODY stages the human-readable spec for the mechanic — which is what a stubbed cell has instead of an implementation.

`{{ piece_id }}` in `description` / `verbose` renders as that piece's `title`, resolved AT IMPORT so the scene carries finished prose and the game does no lookup; renaming a piece re-renders every sanction that mentions it. An unknown id is a hard error rather than literal braces shipped to the player.

A cell a doc declares and the scene lacks is CREATED, pointed at `sanction_stub.tscn` — which keeps the sanction grid doc-first like every other kind, and is the honest state for a sanction whose event is unwritten. Checked by running the spec importer; the two unit tests that covered this (`test_SanctionSpec.gd`, `test_FactionRosters.gd`) were cut as spec/authored-content tests.

`EventSanctionStub` (`scenes/scenario_events/sanction_stub.tscn`) is the no-op payload for a cell whose real event is not written yet. It fires, logs, starts its cooldown and supersedes its parent, so the whole sanction grid is playable and testable before the payloads exist. Leaving `Sanction.event_scene` null instead is worse than it looks for an ACTIVE cell: `Sanction.activate` refuses outright, so the button arms and never disarms, which reads as a bug rather than as unfinished work. (A PASSIVE cell is the exception and carries no payload at all — see below.) What is still stubbed is what the gdd docs themselves mark stubbed: the Colonials' Blizzard and Gunship, and the Anarchists' Mortar 1/2/3. `test_sanction_payloads_match_what_is_built` pins the boundary in both directions, so neither a stub nor a payload can quietly take the other's place.

## A sanction may have nowhere to be aimed


`Sanction.needs_target` (default true) marks a sanction that is FIRED but not PLACED. Global EMP is the case: it reaches every unit on the map, so asking the player where to put it would be theatre — and worse, it would leave the sanction armed and waiting on a click that cannot mean anything, which a right-click meant for their units would then set off by accident.

An un-aimed sanction never becomes `RTSController._pending_sanction` at all: pressing its button IS the deployment. `can_target` short-circuits for one too, so the fog gate cannot refuse a thing that has no point to check.

**Distinct from `passive`, and the two are not on a scale.** A passive is never fired and never appears on the bar; an un-aimed sanction is fired deliberately, costs a charge and runs its cooldown — it simply has nowhere to be pointed.

## A passive sanction is unlocked, never deployed


**Passivity belongs to the ABILITY, not to a cell.** It is authored once at the top of the ability doc — Scavenge 2 is not more passive than Scavenge 1 — and the importer stamps it onto each of that ability's cells, so `Sanction.passive` is a snapshot rather than a second authored fact. A `passive:` written inside a level is a hard error naming the top-level key.

**What "passive" means:** the ability is not emitted through a command at all. It is attached to whoever owns it and present persistently, which is why it has no aim point, no cooldown and no button. `Sanction.passive` marks a cell whose PURCHASE is the whole thing: it grants a standing benefit for the rest of the match, takes no aim point, runs no cooldown, and `SanctionGrid.is_deployable` keeps it off the deploy bar entirely — a button that did nothing when pressed would read as broken. `activate()` refuses one outright as well, because that is the choke point the bot walks too.

`deployable_sanctions()` and `standing_sanctions()` PARTITION the owned, non-superseded set, so every cell the player has paid for is doing exactly one of the two things. A passive is otherwise an ordinary cell: it costs dominion, occupies a grid slot, pays its share of the tier toll, and is superseded by its own upgrade.

The Anarchists' **Scavenge** family is what this exists for — "collect resources on each enemy kill" is a rule about the whole match with no moment to aim it at. `Commander.kill_bounty_rate()` is the MAXIMUM over standing sanctions rather than the sum: a column is one sanction the player improves, so Scavenge 2 replacing Scavenge 1 must pay 20%, not 30%. Supersession already drops the parent, so the two agree today; max is what keeps them agreeing if a faction ever authors two unrelated bounty passives, where stacking into a refund larger than the unit's price would print money.

**The bounty is paid from `Entity.receive_damage`, not from a death handler**, because that is the one place the KILLER is known — a death handler sees only the corpse. What that cannot pay for is the honest consequence: a unit that starves, is scuttled, or dies to an unattributed effect pays nobody, which is right, because those are not kills. Friendly fire is excluded outright so you can never fund yourself off your own losses, and an unpriced piece (neutral scenery, a scenario-only entity) pays 0 rather than erroring. Tests: `tests/test_KillBounty.gd`.
