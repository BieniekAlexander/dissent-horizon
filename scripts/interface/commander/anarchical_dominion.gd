class_name AnarchicalDominion
extends DominionRoute

## The Anarchical dominion route: friendly infantry standing with a Warlord bank dominion
## every cycle. Authored as the [b]Retinue[/b] passive ability — see
## gdd/factions/anarchical/abilities/retinue.md.
##
## RUN ONCE PER COMMANDER RATHER THAN ONCE PER WARLORD, and the de-duplication is why: a unit
## inside two Warlords' reaches is ONE follower. Per-piece generators (the shape
## OccupantDominionGenerator uses for the Colonial camp) cannot see each other, so stacking
## Warlords on one squad would double the income and the strategy would degenerate into a
## pile of Warlords with nobody to lead.
##
## WHICH PIECES ARE SOURCES IS THE ABILITY, not a piece id. It used to name
## `an_bioMedium_dominionGen` outright, which made "is this a dominion aura" a fact about one
## unit rather than a capability — so a second such piece (an upgraded Warlord, another
## faction's answer to the same idea) needed code. Now it asks what a piece GRANTS, and a
## second source needs a doc.
##
## The REACH is the piece's own `DominionRegion` collider, which is also what the info
## panel's passive card paints on hover (`reveals: DOMINION`). One shape, swept by this and
## drawn by the HUD, so the ring and the rule cannot come to disagree.

#region Properties
## The passive that makes a piece a dominion aura. Named here rather than authored, because
## exactly one ability is this mechanic; it becomes a doc key on the day a second faction
## wants its own version, exactly as Abilities.SUPPORT_ABILITY will.
const ABILITY_ID: StringName = &"retinue"

## The collider each source sweeps. Found by NAME, the way every component finds its shapes;
## EntityRanges finds the same node by its `debug_shape_*` group for drawing. Neither depends
## on the other.
const REGION_NODE: String = "DominionRegion"

## Dominion awarded per follower per tick cycle. Stays an EXPORT rather than becoming a
## constant: the prologue scenarios deliberately tune it down to 1, and a constant would
## silently restore full-game income there.
##
## FRACTIONAL, so a follower's share is tracked in `_carry` and paid out as it adds up to whole
## dominion, as the Libertarian route does. 3.33 per 5 s is 0.67/s a follower: retuned from 5
## (1/s) on 2026-10-05 so the Anarchist route earns about 3x the Technocratic Lab route over a
## game (gdd/systems/macroeconomics/pacing/dominion-rate-analysis.md §Retuned rates).
@export var dominion_per_unit: float = 3.33
static var TICK_RATE: int = 150
## Dominion earned but not yet paid, below one whole point.
var _carry: float = 0.0
## Physics ticks since the last sweep. Private: nothing outside drives this cycle.
var _ticks_elapsed: int = 0
#endregion


#region Public API
## The Warlords (or anything else granting Retinue) this commander owns and can act with.
func sources() -> Array[Commandable]:
	var out: Array[Commandable] = []
	if commander == null:
		return out
	for node: Node in commander.get_children():
		var piece := node as Commandable
		if piece != null and is_instance_valid(piece) and piece.is_built and grants_aura(piece):
			out.append(piece)
	return out


## A route with no STRUCTURE sources: the Warlord is trained, not built, so the base route's
## `structure_sources` stays empty and the bot's build ladder has nothing to do for it.


## Whether `a_piece` projects a dominion aura at all — i.e. whether it grants Retinue.
static func grants_aura(a_piece: Commandable) -> bool:
	if a_piece == null or not is_instance_valid(a_piece):
		return false
	var pool := a_piece.get_node_or_null("Abilities") as Abilities
	return pool != null and pool.grants(ABILITY_ID)


## The followers inside ONE source's reach, WITHOUT the cross-source de-duplication.
##
## Static, and separate from `followers()`, because the two answer different questions. The
## sweep needs the de-duplicated set — that is the mechanic. The HUD needs this one: a card on
## a Warlord says what THAT Warlord is claiming, and subtracting a follower because a
## different Warlord also reaches it would make the card unreadable ("why does mine say two?")
## for a rule the player cannot see from here.
static func followers_of(a_source: Commandable) -> Array[Commandable]:
	var out: Array[Commandable] = []
	if not grants_aura(a_source) or not a_source.is_inside_tree():
		return out
	var region := a_source.get_node_or_null(REGION_NODE) as CollisionShape3D
	if region == null or region.shape == null:
		return out
	for entity: Entity in SU.entities_within(
		a_source.get_world_3d(),
		a_source.hull(),
		region.shape,
		a_source.global_position,
		CollisionLayers.Mask.MOVEMENT_OBSTRUCTION
	):
		var follower := entity as Commandable
		if follower == null or follower == a_source:
			continue
		if follower.commander_id != a_source.commander_id:
			continue
		if follower.defense == null or follower.defense.frame_type != Defense.FrameType.BIO:
			continue
		if grants_aura(follower):  # a second Warlord is a peer, not a follower
			continue
		out.append(follower)
	return out


## What `a_source` WOULD bank this cycle on its own — what its info card reports. The sweep
## may pay less, because a follower two Warlords share is paid for once.
##
## An INSTANCE method because the rate is authored per scenario (see dominion_per_unit), so
## pricing a follower means finding the node that owns the number — which is what
## `for_commander` is for.
func dominion_for(a_source: Commandable) -> float:
	return followers_of(a_source).size() * dominion_per_unit


## The instance driving `a_commander`, or null when its faction has no dominion aura at all.
##
## A subtree search, so callers resolve it ONCE and hold the reference — the info card does
## this when it is built rather than on every frame it is drawn.
static func for_commander(a_commander: Commander) -> AnarchicalDominion:
	if a_commander == null or not is_instance_valid(a_commander):
		return null
	var found: Array[Node] = a_commander.find_children("*", "AnarchicalDominion", true, false)
	return found[0] as AnarchicalDominion if not found.is_empty() else null


## The distinct friendly followers currently inside ANY source's reach — what the sweep pays
## for, and what the economy readout names beside the rate.
##
## A follower is a friendly BIO piece that is not itself a source: the claim is on units led,
## so a Warlord never counts itself or another Warlord.
func followers() -> Array[Commandable]:
	var seen: Dictionary = {}
	var out: Array[Commandable] = []
	for source: Commandable in sources():
		for follower: Commandable in followers_of(source):
			if seen.has(follower):
				continue
			seen[follower] = true
			out.append(follower)
	return out


#endregion


#region Lifecycle
func _proc() -> void:
	var count: int = followers().size()
	if count <= 0 or commander == null:
		return
	_carry += count * dominion_per_unit
	var whole: int = floori(_carry)
	if whole > 0:
		_carry -= whole
		commander.add_dominion(whole)


func _physics_process(_a_delta: float) -> void:
	_ticks_elapsed += 1
	if _ticks_elapsed % TICK_RATE == 0:
		_proc()
#endregion
