class_name Deployment
extends RefCounted

## A slot's deferred deployment: the drops it still holds, where each may land, and landing one.
##
## The drops are cast by the COMMANDER — nothing on the map casts them — so this is the whole
## ordnance, not a command handed to a caster. The player's HUD and the bot both land a drop
## through `drop`, which is what makes it the same order for both; the rules are stated here
## once. Rules and rationale: gdd/systems/scenario-scripting/starting-formations.md
## §Deferred deployment.
##
## A commander holds one of these only while its scenario deploys by drop
## (Scenario.uses_deferred_deployment); it is created with the slot's starting bank, which is
## held back until the command centre lands.

## A charge was spent or granted. The HUD redraws the deployment panel and the economy bars on it.
signal changed

enum Drop { COMMAND_CENTRE, EXTRACTOR }

## Why a drop may not land where it was aimed. OK is the only verdict `drop` acts on.
enum Verdict { OK, NO_CHARGE, OUT_OF_VISION, BAD_FOOTPRINT, UNITS_IN_THE_WAY }

## Extractor drops granted when the command centre lands. The design fixes it at two for every
## faction; a per-faction count would be a Faction export, and nothing asks for one yet.
const EXTRACTOR_DROP_CHARGES: int = 2

## The command centre each faction drops, by the faction's scene. Hardcoded rather than read
## off the faction doc: a command centre is what every deployment starts from, not a starting
## piece a faction chooses. A faction missing here cannot deploy by drop.
const COMMAND_CENTRE_SCENES: Dictionary = {
	"res://scenes/factions/anarchical.tscn":
	"res://scenes/entities/structures/an/an_commandCenter.tscn",
	"res://scenes/factions/colonial.tscn":
	"res://scenes/entities/structures/cl/cl_commandCenter.tscn",
	"res://scenes/factions/libertarian.tscn":
	"res://scenes/entities/structures/lb/lb_commandCenter.tscn",
	"res://scenes/factions/technocratic.tscn":
	"res://scenes/entities/structures/tc/tc_commandCenter.tscn",
}

## What an extractor drop puts down: a neutral site, and the slot's extractor on it. The pair the
## removed starting extractors used, so the free extractors are the ordinary pieces.
const EXTRACTION_SITE_SCENE: String = "res://scenes/entities/structures/nt/nt_extractionSite.tscn"
const EXTRACTOR_SCENE: String = "res://scenes/entities/structures/nt/nt_extractor.tscn"

## How far past the footprint's longer side an own unit on it looks for somewhere to stand, in
## cells: room for the widest size class's erosion. A unit that finds nothing stays put.
const DISPLACE_MARGIN_RINGS: int = 4

## How high above its spot the structure's model starts, in world units, and how long it takes
## to settle. Presentation only: the structure is in play at the instant of the drop.
const DESCENT_HEIGHT: float = 12.0
const DESCENT_SECONDS: float = 2.0

var _commander: Commander
## Drop -> charges left.
var _charges: Dictionary = {Drop.COMMAND_CENTRE: 1, Drop.EXTRACTOR: 0}
## The slot's starting resources, credited when the command centre lands.
var _bank_energy: int
var _bank_dominion: int
## Drop -> {dims, allow_uneven, is_production}: read once off probe instances of the drop's
## scenes. Memoized because reading it instantiates a whole piece scene, and the verdict is
## asked every frame the drop is armed.
var _footprint_rules: Dictionary = {}


func _init(a_commander: Commander, a_bank_energy: int, a_bank_dominion: int) -> void:
	_commander = a_commander
	_bank_energy = a_bank_energy
	_bank_dominion = a_bank_dominion


## The command centre this commander's faction drops (COMMAND_CENTRE_SCENES), or null for a
## faction with none. Asked lazily: the commander's faction is instanced in its _ready, after
## the Deployment is made.
func command_centre_scene() -> PackedScene:
	var faction: Faction = _commander.faction
	if faction == null or not COMMAND_CENTRE_SCENES.has(faction.scene_file_path):
		return null
	return load(COMMAND_CENTRE_SCENES[faction.scene_file_path]) as PackedScene


## The piece id of every faction's command centre: the scene's basename, which the importer
## makes the piece id (CLAUDE.md §Piece ids). Derived from COMMAND_CENTRE_SCENES, so a new
## faction's entry there is the whole of declaring its command centre — the HEGEMONY win
## condition (Scenario.win_condition) and the bot's objective both read this.
static func command_centre_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for path: String in COMMAND_CENTRE_SCENES.values():
		var id: StringName = StringName(path.get_file().get_basename())
		if not out.has(id):
			out.append(id)
	return out


static func is_command_centre_id(a_id: StringName) -> bool:
	return command_centre_ids().has(a_id)


## Whether `a_piece` is a command centre, by its piece id.
static func is_command_centre(a_piece: Actor) -> bool:
	return a_piece != null and is_command_centre_id(a_piece.id)


#region Charges
func charges(a_drop: Drop) -> int:
	return int(_charges[a_drop])


func has_charge(a_drop: Drop) -> bool:
	return charges(a_drop) > 0


## Whether the command centre is down — which is also what ends the pre-drop phase.
func has_landed_command_centre() -> bool:
	return not has_charge(Drop.COMMAND_CENTRE)


## Whether every drop has been spent; the deployment panel goes with the last one.
func is_spent() -> bool:
	return _charges.values().all(func(a_count: int) -> bool: return a_count <= 0)


#endregion


#region Where a drop may land
## Whether `a_drop` may land centred on `a_xz`, and if not, why.
##
## Every cell of the footprint must be in the commander's CURRENT vision, the footprint must
## be one the piece could be built on, and no other commander's unit may stand on it. The
## commander's own units on it are no bar — `drop` moves them off.
func verdict(a_drop: Drop, a_xz: Vector2) -> Verdict:
	if not has_charge(a_drop):
		return Verdict.NO_CHARGE
	var map: Map = _commander.map
	var rule: Dictionary = _footprint_rule(a_drop)
	var dims: Vector2i = rule["dims"]
	var message := CommandMessage.new(map, null, null, Vector3(a_xz.x, 0.0, a_xz.y))
	# Never onto a site or into a pond, for either drop: allow_submerged is never granted, and
	# an occupied cell (a site is one) fails the footprint outright.
	if not Structure.valid_placement(message, dims, rule["allow_uneven"], false):
		return Verdict.BAD_FOOTPRINT
	var cells: Array[Vector2i] = map.footprint_cells(a_xz, dims)
	if not cells.all(
		func(a_cell: Vector2i) -> bool: return _commander.has_vision_at(map.grid_to_world(a_cell))
	):
		return Verdict.OUT_OF_VISION
	if _has_foreign_units_on(footprint_area(map, map.footprint_origin(a_xz, dims), dims)):
		return Verdict.UNITS_IN_THE_WAY
	return Verdict.OK


## The footprint `a_drop` claims, as dimensions in cells.
func footprint_dims(a_drop: Drop) -> Vector2i:
	return _footprint_rule(a_drop)["dims"]


## The scene whose model a drop shows while aimed: the structure it puts down.
func preview_scene(a_drop: Drop) -> PackedScene:
	match a_drop:
		Drop.COMMAND_CENTRE:
			return command_centre_scene()
		_:
			return load(EXTRACTOR_SCENE) as PackedScene


## The scene that fixes `a_drop`'s footprint rule: the extraction site for an extractor drop,
## since the extractor stands on it rather than on the ground.
func _footprint_scene(a_drop: Drop) -> PackedScene:
	if a_drop == Drop.EXTRACTOR:
		return load(EXTRACTION_SITE_SCENE) as PackedScene
	return preview_scene(a_drop)


func _footprint_rule(a_drop: Drop) -> Dictionary:
	if not _footprint_rules.has(a_drop):
		assert(
			_footprint_scene(a_drop) != null,
			(
				"Deployment: nothing to drop for %s — a faction " % Drop.keys()[a_drop]
				+ "missing from COMMAND_CENTRE_SCENES"
			)
		)
		var probe: Node = _footprint_scene(a_drop).instantiate()
		var structure := probe.get_node_or_null("Structure") as Structure
		_footprint_rules[a_drop] = {
			"dims": structure.dimensions if structure != null else Vector2i.ONE,
			"allow_uneven": structure.allow_uneven if structure != null else false,
			"is_production": _preview_has_production(a_drop),
		}
		probe.free()
	return _footprint_rules[a_drop]


## Whether what `a_drop` puts down trains units — how the bot's placement score weighs a spot.
func is_production(a_drop: Drop) -> bool:
	return _footprint_rule(a_drop)["is_production"]


func _preview_has_production(a_drop: Drop) -> bool:
	var probe: Node = preview_scene(a_drop).instantiate()
	var has_production: bool = Production.node_trains_units(probe)
	probe.free()
	return has_production


## The world XZ rectangle a `a_dims` footprint anchored at cell `a_origin` covers.
static func footprint_area(a_map: Map, a_origin: Vector2i, a_dims: Vector2i) -> Rect2:
	var first: Vector2 = VU.in_xz(a_map.grid_to_world(a_origin))
	var last: Vector2 = VU.in_xz(a_map.grid_to_world(a_origin + a_dims - Vector2i.ONE))
	var half_cell: Vector2 = Vector2.ONE * Map.CELL_SIZE * 0.5
	return Rect2(first.min(last) - half_cell, (last - first).abs() + half_cell * 2.0)


## Every ground unit whose body overlaps `a_area`. A flier over a spot does not stand on it.
func units_on(a_area: Rect2) -> Array:
	return _ground_units().filter(
		func(a_unit: Actor) -> bool:
			return overlaps(
				VU.in_xz(a_unit.global_position),
				a_unit.bounding_radius(CollisionLayers.Mask.MOVEMENT_OBSTRUCTION),
				a_area
			)
	)


func _has_foreign_units_on(a_area: Rect2) -> bool:
	return units_on(a_area).any(
		func(a_unit: Actor) -> bool: return a_unit.commander_id != _commander.id
	)


## Every unit on the map that stands on the ground, whoever owns it.
func _ground_units() -> Array:
	return _commander.get_tree().get_nodes_in_group("unit").filter(
		func(a_node: Node) -> bool: return a_node is Actor and Aerial.of(a_node) == null
	)


## Whether a body of `a_radius` standing at `a_xz` reaches into `a_area`.
static func overlaps(a_xz: Vector2, a_radius: float, a_area: Rect2) -> bool:
	var nearest: Vector2 = a_xz.clamp(a_area.position, a_area.end)
	return a_area.has_point(a_xz) or a_xz.distance_to(nearest) < a_radius


#endregion


#region Landing a drop
## Land `a_drop` centred on `a_xz` and return the actors it put in play — the command centre,
## or the extractor (its site is neutral, and is no actor). Empty, and nothing changes, when
## the verdict is not OK.
func drop(a_drop: Drop, a_xz: Vector2) -> Array[Actor]:
	var landed: Array[Actor] = []
	if verdict(a_drop, a_xz) != Verdict.OK:
		return landed
	var map: Map = _commander.map
	var dims: Vector2i = footprint_dims(a_drop)
	var origin: Vector2i = map.footprint_origin(a_xz, dims)
	var centre: Vector2 = VU.in_xz(map.footprint_centroid(origin, dims))
	var displaced: Array = units_on(footprint_area(map, origin, dims))
	match a_drop:
		Drop.COMMAND_CENTRE:
			landed.append(_land(preview_scene(a_drop), centre))
			_commander.add_energy(_bank_energy)
			_commander.add_dominion(_bank_dominion)
			_charges[Drop.EXTRACTOR] = EXTRACTOR_DROP_CHARGES
		Drop.EXTRACTOR:
			_land_site(centre)
			landed.append(_land(preview_scene(a_drop), centre))
	_charges[a_drop] = charges(a_drop) - 1
	# After the structure is registered, so the ground it now holds is no longer a place to
	# stand. verdict() has already refused the spot if any of these were someone else's.
	for unit: Actor in displaced:
		_step_off(unit, map, maxi(dims.x, dims.y) + DISPLACE_MARGIN_RINGS)
	changed.emit()
	return landed


## Put one `a_scene` structure in play for the commander at `a_centre`, its model descending.
func _land(a_scene: PackedScene, a_centre: Vector2) -> Actor:
	var structure: Actor = a_scene.instantiate() as Actor
	_commander.map.add_entities([structure], a_centre, _commander)
	var model := structure.get_node_or_null("MeshVisual") as MeshVisual
	if model != null:
		model.play_descent(DESCENT_HEIGHT, DESCENT_SECONDS)
	return structure


## Put a neutral extraction site at `a_centre`, for an extractor drop to stand on.
func _land_site(a_centre: Vector2) -> void:
	var neutral: Commander = _commander.scenario.commanders[0]
	_commander.map.add_entities(
		[(load(EXTRACTION_SITE_SCENE) as PackedScene).instantiate()], a_centre, neutral
	)


## Move `a_unit` to the nearest ground its size class can stand on, searching outward from where
## it stands. A unit that finds none within `a_max_rings` is left where it is.
static func _step_off(a_unit: Actor, a_map: Map, a_max_rings: int) -> void:
	var at: Vector2i = a_map.world_to_grid(VU.in_xz(a_unit.global_position))
	for ring: int in range(1, a_max_rings + 1):
		var best: Variant = null
		var best_distance: float = INF
		for cell: Vector2i in _ring_cells(at, ring):
			var xz: Vector2 = (
				VU.in_xz(a_map.grid_to_world(cell))
				if a_map.grid_coordinates_in_bounds(cell)
				else Vector2.INF
			)
			if xz == Vector2.INF or not DebugPlacement.figure_admits(a_unit, a_map, xz):
				continue
			var distance: float = xz.distance_squared_to(VU.in_xz(a_unit.global_position))
			if distance < best_distance:
				best_distance = distance
				best = xz
		if best != null:
			var xz: Vector2 = best
			a_unit.global_position = Vector3(xz.x, a_map.terrain_height_at(xz), xz.y)
			return


## The cells at L-infinity distance exactly `a_ring` from `a_center`.
static func _ring_cells(a_center: Vector2i, a_ring: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dx: int in range(-a_ring, a_ring + 1):
		for dz: int in range(-a_ring, a_ring + 1):
			if maxi(absi(dx), absi(dz)) == a_ring:
				cells.append(a_center + Vector2i(dx, dz))
	return cells
#endregion
