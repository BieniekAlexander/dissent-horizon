class_name OrdnanceDepot
extends RefCounted

## Free charges of ordnance a commander holds WITHOUT a caster piece — what a courier pod
## hands over. A charge here is cast by the commander directly and is never recharged: the
## depot is a purse, not a pool. It casts through the commander's own sanction grid when that
## has a cell for the ability, and otherwise through the lowest level ANY faction authors of
## it, so a Colonial who recovers an Anarchist dispatch can still call the barrage in.
## Rules: gdd/systems/combat/environmental-pieces.md §The ordnance depot.

## The faction scenes a cross-faction grant is looked up in. Empty until first asked for, then
## every faction that can take the field — the set that can deploy a command centre
## (Deployment). A test installs fixture scenes here and empties it again afterwards.
static var faction_scenes: Array[PackedScene] = []

## ability id -> the lowest-level Sanction any faction authors for it. Memoized because filling
## it instantiates every faction scene, and the authored grids never change in a run. A test
## that swaps faction_scenes calls reset_foreign_sanctions.
static var _foreign_sanctions: Dictionary = {}
static var _foreign_sanctions_filled: bool = false

var _commander: Commander
## ability id -> charges held.
var _charges: Dictionary = {}


func _init(a_commander: Commander) -> void:
	_commander = a_commander


func grant(a_ability_id: StringName, a_count: int) -> void:
	if a_ability_id == &"" or a_count <= 0:
		return
	_charges[a_ability_id] = charges_of(a_ability_id) + a_count


func charges_of(a_ability_id: StringName) -> int:
	return int(_charges.get(a_ability_id, 0))


func has_charge(a_ability_id: StringName) -> bool:
	return charges_of(a_ability_id) > 0


func granted_abilities() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: Variant in _charges:
		if int(_charges[id]) > 0:
			out.append(StringName(id))
	return out


## Take one charge. False — taking nothing — when there is none.
func spend(a_ability_id: StringName) -> bool:
	if not has_charge(a_ability_id):
		return false
	_charges[a_ability_id] = charges_of(a_ability_id) - 1
	if _charges[a_ability_id] == 0:
		_charges.erase(a_ability_id)
	return true


## The sanction a depot cast of `a_ability_id` fires through, or null when no faction authors
## one: the cell of the commander's own grid in play when it owns one, else the lowest-tier cell
## granting the ability there, else the lowest level of it on any faction's grid. A Sanction
## holds no per-commander state (the caster counts the cooldown, and the depot never recharges),
## so the foreign one is the shared template itself.
func sanction_for(a_ability_id: StringName) -> Sanction:
	var grid: SanctionGrid = _commander.sanction_grid if _commander != null else null
	var entry: SanctionGrid.Entry = grid.entry_for_ability(a_ability_id) if grid != null else null
	if entry != null:
		return entry.sanction
	return foreign_sanction_for(a_ability_id)


## The lowest level of `ability_id` authored on ANY faction's grid, or null (see sanction_for).
static func foreign_sanction_for(ability_id: StringName) -> Sanction:
	if not _foreign_sanctions_filled:
		_foreign_sanctions_filled = true
		if faction_scenes.is_empty():
			for path: String in Deployment.COMMAND_CENTRE_SCENES:
				faction_scenes.append(load(path) as PackedScene)
		for scene: PackedScene in faction_scenes:
			var faction: Faction = scene.instantiate() as Faction if scene != null else null
			if faction == null:
				continue
			for sanction: Sanction in (
				OrdnanceDepot.lowest_sanctions_in(faction.sanction_unlocks).values()
			):
				var held: Sanction = _foreign_sanctions.get(sanction.ability_id)
				if held == null or sanction.ability_level < held.ability_level:
					_foreign_sanctions[sanction.ability_id] = sanction
			faction.free()
	return _foreign_sanctions.get(ability_id)


## ability id -> the lowest-tier non-passive sanction among `unlocks`, one grid's worth.
static func lowest_sanctions_in(unlocks: Array) -> Dictionary:
	var lowest: Dictionary = {}
	for unlock: SanctionUnlock in unlocks:
		if unlock == null or unlock.sanction == null or unlock.sanction.passive:
			continue
		var held: SanctionUnlock = lowest.get(unlock.sanction.ability_id)
		if held == null or unlock.tier < held.tier:
			lowest[unlock.sanction.ability_id] = unlock
	var out: Dictionary = {}
	for id: Variant in lowest:
		out[id] = lowest[id].sanction
	return out


## Forget the memoized foreign sanctions, so the next lookup reads faction_scene_paths afresh.
static func reset_foreign_sanctions() -> void:
	_foreign_sanctions = {}
	_foreign_sanctions_filled = false


## Cast `a_ability_id` from the depot at `a_position` (a unit `a_target` for a single-unit
## cast, a cargo `a_payload` for one that takes it). The charge is spent only on a cast that
## lands, as UseSanction spends only on success. The commander's command centre stands in as
## the caster: an off-map event keys its entry edge to the caster, so the barrage comes over
## the commander's own side of the field rather than whichever edge is nearest the aim point.
func cast(
	a_ability_id: StringName,
	a_position: Vector3,
	a_target: Variant = null,
	a_payload: StringName = &""
) -> bool:
	if not has_charge(a_ability_id):
		return false
	var sanction: Sanction = sanction_for(a_ability_id)
	var manager: ScenarioTriggerManager = (
		_commander.scenario_event_manager() if _commander != null else null
	)
	if sanction == null or manager == null:
		return false
	var anchor: Actor = _commander.command_centre()
	if not sanction.activate(a_position, manager, _commander, anchor, a_payload, a_target):
		return false
	return spend(a_ability_id)
