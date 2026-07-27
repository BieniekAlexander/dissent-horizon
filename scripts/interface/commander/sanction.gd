class_name Sanction extends Resource

## ONE CELL of the sanction grid: a dominion-unlocked level of an ability, which the player
## can activate at a chosen map position.
##
## "Sanction" means exactly one thing — unlocked with the DOMINION resource — so this is an
## UNLOCK ROUTE and not a kind of thing. What it grants is an ABILITY, defined by a
## `kind: AbilityDefinition` doc and read at runtime through [AbilityCatalog]; the same ability could
## as easily have been free or bought at a structure, and nothing else about it would
## change. The per-CELL facts (this level's copy, cooldown and aim rules) live here because
## they belong to the level rather than to the ability.
##
## On activation it instantiates `event_scene` — a scene whose root is an
## AbstractEvent — positions it at the target, executes it, then frees it. A
## cooldown gates re-use.
##
## Sanctions are data, not code: this is the one and only Sanction class. Each
## instance is authored (name, cooldown, event scene) and wrapped in an
## SanctionUnlock on a Faction's sanction grid; the specific behaviour lives in the
## referenced event scene rather than in an Sanction subclass. SanctionGrid
## duplicates it per-commander so cooldowns are independent.

## How the bot aims this sanction (the human aims it by clicking). The chosen
## engagement zone is the same — defend the base, else strike the enemy — but the
## aim point within it differs by sanction kind. See BotSanction.
enum Targeting {
	## Aim at the densest cluster of enemy units, to maximise an area effect
	## (e.g. Irradiate's radiation field).
	ENEMY_CLUSTER,
	## Aim where freshly-spawned allies should land: at the defended structure when
	## defending, on our side of the front when attacking (e.g. Ambush's irregulars).
	REINFORCE,
}

## Display name, shown on the sanction bar button.
@export var sanction_name: String = ""

## What this sanction does, in the player's terms — shown as the sanction bar button's
## hover tooltip. Lives here rather than on SanctionUnlock because it describes the
## SANCTION, not the cost of acquiring it: the same text is what the player wants to read
## while deciding whether to unlock it and later while deciding where to aim it.
##
## Blank is fine and shows no tooltip at all (see VerboseTooltipButton), so an
## un-described sanction degrades to the current behaviour rather than an empty popup.
@export_multiline var description: String = ""

## The long tier of the sanction's tooltip, shown while `ui_verbose` is held. Optional:
## blank means the HUD shows `description` above the synthesized numbers, which is the
## normal case. Authored in the sanction's gdd doc as `verbose:`, beside the short one, so
## a piece's two tiers of copy live together rather than one in markdown and one in a scene.
@export_multiline var verbose_description: String = ""

## Seconds before a CASTER that has fired this can fire it again. Per building, not per
## commander: each caster runs its own timer, so a second Operations Center is a second
## Scan rather than a faster one.
@export var cooldown_duration: float = 60.0

## Scene instantiated and executed when this sanction activates. Its root node
## must be (or extend) AbstractEvent.
@export var event_scene: PackedScene

## Whether this sanction is AIMED at all. True for almost everything — a sanction is
## normally a thing you place. False for the ones whose effect has no location: Global
## EMP reaches every unit on the map, so asking the player where to put it would be
## theatre, and worse, it would leave the sanction armed and waiting on a click that
## cannot mean anything.
##
## An un-aimed sanction fires the moment its button is pressed. It never becomes the
## controller's `_pending_sanction`, so it cannot be armed, cancelled, or set off by a
## later right-click meant for something else.
##
## Distinct from `passive`, and the two are not on a scale: a passive is never fired at
## all, while this one is fired deliberately and simply has nowhere to be pointed. It
## still costs a charge and still runs its cooldown.
@export var needs_target: bool = true

## Whether the target point must be lit by this commander's LIVE vision (see
## can_target). Ignored entirely when `needs_target` is false — there is no point to
## check. True for almost everything: calling a strike down blind into the shroud
## is exactly what scouting is supposed to cost, so the fog gate is the default and an
## sanction opts OUT of it rather than into it.
##
## False is for the sanctions whose whole job is to see — a scan reveals the fog, so
## requiring vision of the spot first would make it useful only where it is not needed.
@export var needs_vision: bool = true

## The ABILITY this cell grants, and WHICH LEVEL of it.
##
## An ability has levels; a cell grants one of them. `drop1` at level 2 is the same ability
## as `drop1` at level 1, improved — so the higher one REPLACES the lower in play, and the
## commander casts whichever level it has unlocked (see SanctionGrid.effective_level).
##
## THIS IS WHAT DECIDES SUPERSESSION, replacing the parent chain that used to. The two were
## redundant, and the level is the more general of the pair: a single cell can raise
## several abilities at once (Colonial Drop 2 grants `drop2` AND upgrades `drop1`), which a
## chain of one-parent edges cannot express. `parent` survives only as the UNLOCK GATE —
## "you must own that cell before you may buy this one" — which is a different question.
##
## For a family whose cells are simply its own tiers, the ability id is the family id and
## the level is the cell's position in it, which the importer fills in.
@export var ability_id: StringName = &""

## 1-based. 0 for a passive, which is never cast and so has no level to be at.
@export var ability_level: int = 1


## PASSIVITY IS THE ABILITY'S, and this is a SNAPSHOT of it. It is authored once at the top
## of the ability doc — Scavenge 2 is not more passive than Scavenge 1 — and the importer
## stamps it onto every cell of that ability, so there is one authored fact and no way for
## two cells to disagree. A `passive:` written inside a level is a hard error.
##
## A passive ability is never emitted through a command: it is attached to whoever owns it
## and present persistently. Unlocking it IS the whole thing — it grants a standing benefit
## for the rest of the match, takes no aim point and runs no cooldown, and
## SanctionGrid.is_deployable keeps it off the deploy bar entirely — a button that did
## nothing when pressed would read as broken.
##
## The Anarchists' Scavenge family is the case this exists for: "collect resources on
## each enemy kill" is a rule about the whole match, and there is no moment to aim it at.
## It still costs dominion, still occupies a grid cell, still pays its share of the tier
## toll and is still superseded by its own upgrade — a passive is a different kind of
## PAYLOAD, not a different kind of cell.
## The CARGO CHOICES this level offers, as {"piece": StringName, "count": int}. Empty for a
## sanction that simply happens — most of them.
##
## A sanction with payloads is ARMED IN TWO STEPS, exactly as Build is: pressing its button
## drills into a menu of these pieces, picking one sets `CommandMessage.tool`, and the
## right-click that follows delivers that piece. See
## gdd/systems/ux/ui/command-card-and-hotkeys.md §A sanction that takes a tool.
##
## PIECE IDS, not PackedScenes. A resource-valued export inside a Resource crashes the Godot
## inspector, and the id is enough: the scene is resolved at cast time through the Tool
## registry, which is already the project's one id-to-scene map.
##
## Held per LEVEL, which is what makes "upgrading" free: the level that supersedes its parent
## carries the same piece at a higher count, and a column stays one sanction you improve.
@export var payloads: Array[Dictionary] = []

@export var passive: bool = false

## Standing benefit — the fraction of a killed enemy's energy cost paid to this commander
## (0.1 = 10%). Meaningless unless `passive`; see Commander.kill_bounty_rate.
##
## A named field on the shared Sanction rather than an Sanction subclass, matching how
## `effect_radius` / `min_targets` / `targeting` already sit here and matter only to some
## sanctions. A second standing benefit would join it the same way: what makes Sanction
## "the one and only Sanction class" is that BEHAVIOUR lives in the event scene, and a
## passive has no behaviour to put there — only a number.
@export_range(0.0, 1.0, 0.01) var kill_bounty_fraction: float = 0.0

## How the bot aims this sanction.
@export var targeting: Targeting = Targeting.ENEMY_CLUSTER

## World-space radius the sanction's effect covers. The bot uses it to score
## cluster targets — how many enemies a single drop would catch.
@export var effect_radius: float = 6.0

## Minimum enemy units a drop must catch (within effect_radius) for the bot to
## judge an ENEMY_CLUSTER sanction worth spending. Keeps it from wasting a charge
## on a lone scout.
@export var min_targets: int = 2

## An Sanction keeps NO cooldown of its own any more. It used to, back when a sanction was
## a power the commander held; now it is an ability a BUILDING holds, and the charge lives
## with the building (see Abilities) so that owning three casters means three uses on
## three independent timers. `cooldown_duration` above is the number that caster counts.

## The command name this sanction answers to on the grid and in the controller's pending
## sub-mode, e.g. "Scan 2" -> "command_sanction_scan_2".
##
## Sanctions are authored data, so their command names are DERIVED rather than declared in
## a table: adding one is writing a markdown doc, and a hand-maintained name list would be
## a second place for the same fact to live.
const COMMAND_PREFIX: String = "command_sanction_"

func command_name() -> String:
	return command_name_for(sanction_name)

## The command name a sanction CALLED `a_sanction_name` is armed as. Static so the grid can
## build a binding for a level it has only the TITLE of (from abilities.json) without
## instantiating the sanction — and so the derivation exists exactly once. Two copies of this
## expression is precisely how a button and the command it fires would come to disagree.
static func command_name_for(sanction_name: String) -> String:
	return COMMAND_PREFIX + sanction_name.to_snake_case()


## Put the chosen cargo into the event, when this sanction takes one and the caller picked
## one. Written with `set()` on the same optional-property terms as `caster` and
## `sanction_name` above: only an event that declares the fields takes them, and an event with
## its own authored cargo keeps it when nothing was chosen.
func _load_payload(a_event: AbstractEvent, a_payload: StringName) -> void:
	if a_payload == &"" or payloads.is_empty():
		return
	var tool: Tool = Tool.for_id(a_payload)
	if tool == null or tool.packed_scene == null:
		push_error("Sanction '%s': payload '%s' has no scene" % [sanction_name, a_payload])
		return
	a_event.set("entity_scenes", [tool.packed_scene] as Array[PackedScene])
	a_event.set("count", count_of(a_payload))


## How many of `a_piece` this level delivers, or 0 when it does not offer that piece at all.
## A payload naming no count delivers one — the same default a bare entry reads as.
func count_of(a_piece: StringName) -> int:
	for payload: Dictionary in payloads:
		if StringName(str(payload.get("piece", ""))) == a_piece:
			return maxi(1, int(payload.get("count", 1)))
	return 0


## The piece ids this level can deliver, in authored order.
func payload_pieces() -> Array[StringName]:
	var out: Array[StringName] = []
	for payload: Dictionary in payloads:
		out.append(StringName(str(payload.get("piece", ""))))
	return out


## Whether pressing this sanction's button drills into a cargo menu rather than arming
## straight away.
func takes_a_payload() -> bool:
	return not payloads.is_empty()


## True when `commander` may drop THIS sanction at `position` — the fog-of-war gate,
## and the one place `needs_vision` is read.
##
## For a vision-requiring sanction the commander must have LIVE vision there (a unit,
## structure or scout lighting the spot up this tick); having merely explored it once is
## not enough, so it can never be called down blind into the shroud. A null commander is
## unrestricted, matching Commander.has_vision_at's own "no fog rig" fallback (tests,
## the editor).
##
## An INSTANCE method rather than the static it used to be: the answer now depends on
## the sanction being dropped, not on the position alone.
func can_target(a_position: Vector3, a_commander: Commander) -> bool:
	if not needs_target or not needs_vision:
		return true
	return a_commander == null or a_commander.has_vision_at(a_position)


#region Single-unit targeting
## One off-tree instance of `event_scene`, kept to ASK it things — whether it acts on a single
## unit, and which units it accepts — without casting. Built on first question and freed with
## this resource. An instance rather than a script check because `scope` (own units or
## anyone's) is authored per event SCENE, not per script: Freeze 1 and Freeze 2 share one.
var _prototype: AbstractEvent = null

func _notification(a_what: int) -> void:
	if a_what == NOTIFICATION_PREDELETE and is_instance_valid(_prototype):
		_prototype.free()

func _event_prototype() -> AbstractEvent:
	if _prototype == null and event_scene != null:
		_prototype = event_scene.instantiate() as AbstractEvent
	return _prototype

## Whether this sanction acts on exactly one unit, which the order must name — true for every
## sanction whose event is an EventTargetUnit. Such a cast has no area and nothing to search:
## it is aimed at a UNIT, not at a point (see EventTargetUnit).
func targets_one_unit() -> bool:
	return _event_prototype() is EventTargetUnit

## Whether `a_candidate` is a unit this sanction may be cast on for `a_commander`. False for
## a sanction that does not target a single unit. Untyped, like EventTargetUnit.accepts.
func accepts_target(a_candidate: Variant, a_commander: Commander) -> bool:
	var event := _event_prototype() as EventTargetUnit
	if event == null or a_commander == null:
		return false
	return event.accepts(a_candidate, a_commander.id)
#endregion


## Execute the sanction at the given world position on behalf of `commander` by
## instantiating its event scene. The event acts for that commander (spawns its
## units, damages its enemies). Starts the cooldown on success.
##
## `caster` is the BUILDING that fired it, when there is one. Most payloads have no use
## for it — the event is placed at the target and acts there — but a payload that arrives
## from OFF the map derives its entry point from where the caster stands (see
## OffMapArrival), and nothing else in the chain still knows which building that was.
## Optional so a scripted or test deployment with no caster is still expressible.
##
## Returns whether it fired. The single choke point for every deployment path (the
## player's click, the bot, scripted events), so the readiness and vision gates are
## enforced here once rather than at each call site.
func activate(
	a_position: Vector3,
	a_manager: ScenarioTriggerManager,
	a_commander: Commander,
	a_caster: Commandable = null,
	a_payload: StringName = &"",
	a_target: Variant = null
) -> bool:
	# A passive has no deployment. It should never be armed (it is off the bar), but the
	# refusal is here rather than only in the HUD because activate() is the single choke
	# point every path funnels through — the bot walks the sanction grid too.
	#
	# Readiness is NOT checked here: the charge belongs to the caster that is firing, and
	# this object no longer knows which one that is. UseSanction.can_act asks the caster.
	if passive or event_scene == null:
		return false
	if not can_target(a_position, a_commander):
		return false
	# A single-unit cast with no unit it accepts does nothing, and returning false here is what
	# keeps the charge: UseSanction spends only on success. The unit is re-checked at landing
	# because a queued cast can outlive its target's eligibility (it died, it was promoted).
	var one_unit: bool = targets_one_unit()
	if one_unit and not accepts_target(a_target, a_commander):
		return false
	var event: AbstractEvent = event_scene.instantiate() as AbstractEvent
	if event == null:
		return false
	_load_payload(event, a_payload)
	a_manager.add_child(event)
	event.global_position = a_position
	# Events that spawn/own things read commander_id; a no-op on those that don't.
	event.set("commander_id", a_commander.id if a_commander != null else 0)
	# Which sanction called it down. Same optional-property idiom: only an event that
	# declares the field takes it (EventSanctionStub does, to name itself in its log line).
	event.set("sanction_name", sanction_name)
	# And which building fired it, on the same terms — only the off-map payloads declare it.
	event.set("caster", a_caster)
	if one_unit:
		event.set("target_unit", a_target)
	event.execute(a_manager)
	event.queue_free()
	return true
