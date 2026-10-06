class_name PieceFields
extends RefCounted

## The catalogue of PieceField: every value of a piece's doc that the HUD reads out and the
## debug tuning editor edits, and the conversions between the running game's value, what a
## person reads, and what the doc writes. gdd/systems/ux/ui/piece-readouts.md owns the tiers;
## gdd/systems/ux/ui/debug-tuning.md owns what is tunable.
##
## Fields are grouped by scope, because a piece has one of most things but several weapons,
## each with an emission of several phases, and several ability pools.

## Where the generated shape library lives: a shape's id is its file name here.
const SHAPES_DIR: String = "res://resources/generated/shapes/"
const SHAPE_EXTENSION: String = ".tres"
## The generated status-effect id constants, read as a table rather than named one by one.
const STATUS_EFFECT_IDS: String = "res://scripts/generated/status_effect_ids.gd"

## `hits:` names and the targetable layer each one is. Mirrors the importer's spelling.
static var HIT_LAYERS: Dictionary = {
	"ground": CollisionLayers.Mask.TARGETABLE_GROUND,
	"air": CollisionLayers.Mask.TARGETABLE_AIR,
}
## A phase's `impact_mask:` names, as the importer reads them.
static var IMPACT_LAYERS: Dictionary = {
	"terrain": CollisionLayers.Mask.TERRAIN,
	"structures": CollisionLayers.Mask.STRUCTURE_BLOCKER,
	"ground": CollisionLayers.Mask.TARGETABLE_GROUND,
	"air": CollisionLayers.Mask.TARGETABLE_AIR,
}
## Garrison occupancy bits by doc name, per mask.
static var FRAME_BITS: Dictionary = {"BIO": Garrison.FRAME_BIO, "MECH": Garrison.FRAME_MECH}
static var ARMOUR_BITS: Dictionary = {
	"LIGHT": Garrison.ARMOUR_LIGHT,
	"MEDIUM": Garrison.ARMOUR_MEDIUM,
	"STRONG": Garrison.ARMOUR_STRONG
}
static var MOVEMENT_BITS: Dictionary = {
	"GROUNDED": Garrison.MOVEMENT_GROUNDED,
	"HOVERING": Garrison.MOVEMENT_HOVERING,
	"FLYING": Garrison.MOVEMENT_FLYING,
}

## Memoized: the catalogue is a fixed table of closures, built on first use rather than per
## readout refresh.
static var _by_scope: Dictionary = {}


#region The catalogue
## Every field of one scope, in readout order.
static func of_scope(a_scope: PieceField.Scope) -> Array[PieceField]:
	if _by_scope.is_empty():
		_build()
	var fields: Array[PieceField] = []
	fields.assign(_by_scope.get(a_scope, []))
	return fields


## The PIECE and POOL fields drawn under one readout widget.
static func of_widget(a_widget: StringName) -> Array[PieceField]:
	var fields: Array[PieceField] = []
	for scope: PieceField.Scope in [PieceField.Scope.PIECE, PieceField.Scope.POOL]:
		for field: PieceField in of_scope(scope):
			if field.widget == a_widget:
				fields.append(field)
	return fields


static func _build() -> void:
	_by_scope[PieceField.Scope.PIECE] = _piece_fields()
	_by_scope[PieceField.Scope.WEAPON] = _weapon_fields()
	_by_scope[PieceField.Scope.EMISSION] = _emission_fields()
	_by_scope[PieceField.Scope.PHASE] = _phase_fields()
	_by_scope[PieceField.Scope.POOL] = _pool_fields()


static func _piece_fields() -> Array:
	var fields: Array = []
	# Defense.
	var hp := _field(
		&"hp",
		PieceField.Scope.PIECE,
		"hit points",
		["defense", "hp"],
		PieceField.Kind.NUMBER,
		PieceField.Tier.FACE
	)
	hp.read = func(c: Dictionary) -> Variant: return _authored_hp(c)
	hp.write = func(c: Dictionary, old: Variant, new: Variant) -> void: _retune_hp(c, old, new)
	hp.applies = func(c: Dictionary) -> bool: return _defense(c) != null
	fields.append(hp)
	fields.append(
		_property(
			&"hp",
			"armour",
			["defense", "armour"],
			PieceField.Kind.ENUM,
			"Defense",
			"armour_type",
			Defense.ArmourType
		)
	)
	fields.append(
		_property(
			&"hp",
			"frame",
			["defense", "frame"],
			PieceField.Kind.ENUM,
			"Defense",
			"frame_type",
			Defense.FrameType
		)
	)

	# Movement.
	var speed := _field(
		&"speed",
		PieceField.Scope.PIECE,
		"speed",
		["movement", "speed"],
		PieceField.Kind.SPEED_CLASS,
		PieceField.Tier.FACE
	)
	speed.unit = "u/s"
	speed.read = func(c: Dictionary) -> Variant: return _movement(c).speed if _movement(c) else null
	speed.write = func(c: Dictionary, old: Variant, new: Variant) -> void:
		_retune_speed(c, old, new)
	speed.applies = func(c: Dictionary) -> bool: return _movement(c) != null
	fields.append(speed)
	for spec: Array in [
		["turn rate", "turn_rate", "°/s", -1],
		["acceleration", "max_acceleration", "u/s²", -1],
		["deceleration", "max_deceleration", "u/s²", -1],
		["speed held while turning", "min_turn_speed_ratio", "", Movement.Mode.GROUNDED],
		["reverse speed ratio", "reverse_speed_ratio", "", Movement.Mode.HOVERING],
	]:
		var field: PieceField = _property(
			&"speed", spec[0], ["movement", spec[1]], PieceField.Kind.NUMBER, "Locomotion", spec[1]
		)
		field.unit = spec[2]
		var only_mode: int = spec[3]
		field.applies = func(c: Dictionary) -> bool:
			return _movement(c) != null and (only_mode < 0 or _movement(c).mode == only_mode)
		fields.append(field)
	var crush: PieceField = _property(
		&"speed",
		"crush class",
		["movement", "crush_class"],
		PieceField.Kind.ENUM,
		"Locomotion",
		"crush_class",
		Movement.CrushClass
	)
	crush.applies = func(c: Dictionary) -> bool: return _movement(c) != null
	fields.append(crush)
	# The orbit radius of a piece fighting from its orbit is derived from its weapon's reach at
	# import (SpecRegistry._derive_orbit_radius), so it is not offered: a saved edit would be
	# refused by the next import.
	for spec: Array in [
		["orbit radius", "orbit_radius", "u", PieceField.Kind.NUMBER, true],
		["orbit speed", "orbit_speed", "u/s", PieceField.Kind.SPEED_CLASS, false],
	]:
		var field: PieceField = _property(
			&"speed", spec[0], ["aerial", spec[1]], spec[3], "Aerial", spec[1]
		)
		field.unit = spec[2]
		var is_derived_from_reach: bool = spec[4]
		field.applies = func(c: Dictionary) -> bool:
			var aerial: Aerial = _node(c, "Aerial") as Aerial
			return (
				aerial != null
				and aerial.mode == Movement.Mode.FLYING
				and not (is_derived_from_reach and _has_orbit_weapon(c))
			)
		fields.append(field)
	var body: PieceField = _body_radius(&"speed", "body radius", "radius", "MovementBody")
	body.applies = func(c: Dictionary) -> bool: return _movement(c) != null
	fields.append(body)

	# Senses.
	fields.append(
		_shape(
			&"sight", "vision", ["senses", "vision"], "VisionRange", "vision_", PieceField.Tier.FACE
		)
	)
	var detection: PieceField = _shape(
		&"sight",
		"detection",
		["senses", "detection"],
		"DetectionRange",
		"detection_",
		PieceField.Tier.FACE
	)
	detection.is_optional = true
	fields.append(detection)

	# Garrison.
	var capacity: PieceField = _property(
		&"hold",
		"capacity",
		["garrison", "capacity"],
		PieceField.Kind.INTEGER,
		"Garrison",
		"capacity"
	)
	capacity.tier = PieceField.Tier.FACE
	fields.append(capacity)
	for spec: Array in [
		["bunker", "bunker", "bunker"],
		["releasable", "releasable", "releasable"],
		["occupants survive it", "preserve_occupants", "preserve_occupants"],
	]:
		fields.append(
			_property(
				&"hold", spec[0], ["garrison", spec[1]], PieceField.Kind.BOOL, "Garrison", spec[2]
			)
		)
	var bonus := _field(
		&"hold",
		PieceField.Scope.PIECE,
		"reach bonus",
		["garrison", "range_bonus"],
		PieceField.Kind.SHAPE_PAIR,
		PieceField.Tier.VERBOSE
	)
	bonus.unit = "u"
	bonus.options = ["ground_range_"]
	bonus.read = func(c: Dictionary) -> Variant: return _node(c, "Garrison").range_bonus
	bonus.write = func(c: Dictionary, _old: Variant, new: Variant) -> void:
		_node(c, "Garrison").range_bonus = new
		_refresh_reach(c["node"])
	fields.append(bonus)
	for spec: Array in [
		["frames admitted", "frames", "occupiable_frames", FRAME_BITS],
		["armours admitted", "armours", "occupiable_armours", ARMOUR_BITS],
		["movements admitted", "movements", "occupiable_movements", MOVEMENT_BITS],
	]:
		var mask: PieceField = _property(
			&"hold",
			spec[0],
			["garrison", spec[1]],
			PieceField.Kind.FLAGS,
			"Garrison",
			spec[2],
			spec[3]
		)
		fields.append(mask)
	var sentence: PieceField = _property(
		&"hold",
		"sentence",
		["garrison", "sentence_length"],
		PieceField.Kind.NUMBER,
		"Garrison",
		"sentence_length"
	)
	sentence.unit = "s"
	fields.append(sentence)
	bonus.applies = func(c: Dictionary) -> bool: return _node(c, "Garrison") != null
	return fields


static func _weapon_fields() -> Array:
	var fields: Array = []
	for spec: Array in [
		["time between shots", "split_time", "split_time_ticks"],
		["reload", "reload_time", "reload_time_ticks"],
		["startup", "startup_time", "startup_time_ticks"],
	]:
		var field := _field(
			&"weapon",
			PieceField.Scope.WEAPON,
			spec[0],
			[spec[1]],
			PieceField.Kind.NUMBER,
			PieceField.Tier.POPUP
		)
		field.unit = "s"
		field.is_ticks = true
		var property: String = spec[2]
		field.read = func(c: Dictionary) -> Variant: return c["node"].get(property)
		field.write = func(c: Dictionary, _old: Variant, new: Variant) -> void:
			c["node"].set(property, new)
		fields.append(field)
	var clip := _field(
		&"weapon",
		PieceField.Scope.WEAPON,
		"clip",
		["clip_size"],
		PieceField.Kind.INTEGER,
		PieceField.Tier.POPUP
	)
	clip.read = func(c: Dictionary) -> Variant: return (c["node"] as Weapon).clip_size
	clip.write = func(c: Dictionary, _old: Variant, new: Variant) -> void:
		(c["node"] as Weapon).resize_clip(int(new))
	fields.append(clip)
	for spec: Array in [
		["ground reach", "ground", "ground_range_"], ["air reach", "air", "air_range_"]
	]:
		var field := _field(
			&"weapon",
			PieceField.Scope.WEAPON,
			spec[0],
			["reach", spec[1]],
			PieceField.Kind.SHAPE,
			PieceField.Tier.POPUP
		)
		field.unit = "u"
		field.options = [spec[2]]
		field.is_optional = true
		var is_air: bool = spec[1] == "air"
		field.read = func(c: Dictionary) -> Variant:
			var node: CollisionShape3D = (c["node"] as Weapon).range_node(is_air)
			return node.shape if node != null else null
		field.write = func(c: Dictionary, _old: Variant, new: Variant) -> void:
			var node: CollisionShape3D = (c["node"] as Weapon).range_node(is_air)
			if node != null:
				node.shape = new
			_refresh_reach(c.get("piece"))
		field.shape_node = func(c: Dictionary) -> CollisionShape3D:
			return (c["node"] as Weapon).range_node(is_air)
		# A layer the weapon does not hit has no reach to tune.
		var layer: int = HIT_LAYERS["air" if is_air else "ground"]
		field.applies = func(c: Dictionary) -> bool:
			return (c["node"] as Weapon).target_mask & layer != 0
		fields.append(field)
	var melee := _field(
		&"weapon",
		PieceField.Scope.WEAPON,
		"damage",
		["melee_damage"],
		PieceField.Kind.NUMBER,
		PieceField.Tier.POPUP
	)
	melee.read = func(c: Dictionary) -> Variant: return (c["node"] as Weapon).melee_damage
	melee.write = func(c: Dictionary, _old: Variant, new: Variant) -> void:
		(c["node"] as Weapon).melee_damage = new
		(c["node"] as Weapon).invalidate_shot_cache()
	fields.append(melee)
	var melee_type := _field(
		&"weapon",
		PieceField.Scope.WEAPON,
		"damage type",
		["melee_damage_type"],
		PieceField.Kind.ENUM,
		PieceField.Tier.POPUP
	)
	melee_type.options = Damage.Type
	melee_type.read = func(c: Dictionary) -> Variant: return (c["node"] as Weapon).melee_damage_type
	melee_type.write = func(c: Dictionary, _old: Variant, new: Variant) -> void:
		(c["node"] as Weapon).melee_damage_type = new
		(c["node"] as Weapon).invalidate_shot_cache()
	fields.append(melee_type)
	for field: PieceField in [melee, melee_type]:
		field.applies = func(c: Dictionary) -> bool:
			return (c["node"] as Weapon).projectile_scene == null
	var hits := _field(
		&"weapon",
		PieceField.Scope.WEAPON,
		"hits",
		["hits"],
		PieceField.Kind.FLAGS,
		PieceField.Tier.VERBOSE
	)
	hits.options = HIT_LAYERS
	hits.read = func(c: Dictionary) -> Variant:
		return (c["node"] as Weapon).target_mask & CollisionLayers.TARGETABLE_ANY
	hits.write = func(c: Dictionary, _old: Variant, new: Variant) -> void:
		(c["node"] as Weapon).retarget(int(new))
		_refresh_reach(c.get("piece"))
	fields.append(hits)
	for spec: Array in [
		["turret", "turret", PieceField.Kind.BOOL], ["charged", "charged", PieceField.Kind.BOOL]
	]:
		var field := _field(
			&"weapon", PieceField.Scope.WEAPON, spec[0], [spec[1]], spec[2], PieceField.Tier.VERBOSE
		)
		var property: String = spec[1]
		field.read = func(c: Dictionary) -> Variant: return c["node"].get(property)
		field.write = func(c: Dictionary, _old: Variant, new: Variant) -> void:
			c["node"].set(property, new)
		fields.append(field)
	var turret_rate := _field(
		&"weapon",
		PieceField.Scope.WEAPON,
		"turret turn rate",
		["turret_turn_rate"],
		PieceField.Kind.NUMBER,
		PieceField.Tier.VERBOSE
	)
	turret_rate.unit = "°/s"
	turret_rate.read = func(c: Dictionary) -> Variant: return (c["node"] as Weapon).turret_turn_rate
	turret_rate.write = func(c: Dictionary, _old: Variant, new: Variant) -> void:
		(c["node"] as Weapon).turret_turn_rate = new
	turret_rate.applies = func(c: Dictionary) -> bool: return (c["node"] as Weapon).turret
	fields.append(turret_rate)
	return fields


## An emission's own fields. No `write`: an emission is rebuilt from its doc wholesale as it
## enters play (TuningSession), because its phases are a list rather than a set of values.
static func _emission_fields() -> Array:
	var fields: Array = []
	var damage := _field(
		&"weapon",
		PieceField.Scope.EMISSION,
		"damage",
		["damage"],
		PieceField.Kind.NUMBER,
		PieceField.Tier.POPUP
	)
	damage.read = func(c: Dictionary) -> Variant:
		return Payload.of(c["node"]).base_damage if Payload.of(c["node"]) != null else null
	fields.append(damage)
	var damage_type := _field(
		&"weapon",
		PieceField.Scope.EMISSION,
		"damage type",
		["damage_type"],
		PieceField.Kind.ENUM,
		PieceField.Tier.POPUP
	)
	damage_type.options = Damage.Type
	damage_type.read = func(c: Dictionary) -> Variant:
		return Payload.of(c["node"]).damage_type if Payload.of(c["node"]) != null else null
	fields.append(damage_type)
	var blast := _field(
		&"weapon",
		PieceField.Scope.EMISSION,
		"blast",
		["blast"],
		PieceField.Kind.SHAPE,
		PieceField.Tier.VERBOSE
	)
	blast.unit = "u"
	blast.options = ["aoe_"]
	blast.is_optional = true
	blast.read = func(c: Dictionary) -> Variant:
		var payload: Payload = Payload.of(c["node"])
		return payload.hit_shape().shape if payload != null and payload.has_blast() else null
	fields.append(blast)
	var effects := _field(
		&"weapon",
		PieceField.Scope.EMISSION,
		"applies",
		["status_effects"],
		PieceField.Kind.ID_LIST,
		PieceField.Tier.POPUP
	)
	effects.options = status_effect_ids()
	effects.read = func(c: Dictionary) -> Variant: return applied_effects(c["node"])
	fields.append(effects)
	for spec: Array in [["hitscan", "hitscan"], ["aims at the ground under BIO", "bio_ground_aim"]]:
		var field := _field(
			&"weapon",
			PieceField.Scope.EMISSION,
			spec[0],
			[spec[1]],
			PieceField.Kind.BOOL,
			PieceField.Tier.VERBOSE
		)
		var property: String = spec[1]
		field.read = func(c: Dictionary) -> Variant:
			return Payload.of(c["node"]).get(property) if Payload.of(c["node"]) != null else null
		fields.append(field)
	return fields


## One phase's fields, read off an EmissionPhase. Motion values a phase leaves at their
## default are not read out (`applies`): "jitter 0" says nothing.
static func _phase_fields() -> Array:
	var fields: Array = []
	var phase_name := _field(
		&"weapon",
		PieceField.Scope.PHASE,
		"name",
		["name"],
		PieceField.Kind.TEXT,
		PieceField.Tier.VERBOSE
	)
	phase_name.read = func(c: Dictionary) -> Variant: return String((c["node"] as Node).name)
	fields.append(phase_name)
	var preset := _field(
		&"weapon",
		PieceField.Scope.PHASE,
		"motion preset",
		["motion", "preset"],
		PieceField.Kind.ENUM,
		PieceField.Tier.VERBOSE
	)
	preset.options = _preset_enum()
	fields.append(preset)
	var phase_speed := _field(
		&"weapon",
		PieceField.Scope.PHASE,
		"speed",
		["motion", "speed"],
		PieceField.Kind.SPEED_CLASS,
		PieceField.Tier.VERBOSE
	)
	phase_speed.unit = "u/s"
	phase_speed.read = func(c: Dictionary) -> Variant: return (c["node"] as EmissionPhase).speed
	fields.append(phase_speed)
	var coast := _field(
		&"weapon",
		PieceField.Scope.PHASE,
		"coast speed",
		["motion", "coast_speed"],
		PieceField.Kind.SPEED_CLASS,
		PieceField.Tier.VERBOSE
	)
	coast.unit = "u/s"
	coast.read = func(c: Dictionary) -> Variant: return (c["node"] as EmissionPhase).coast_speed
	coast.applies = func(c: Dictionary) -> bool:
		return (c["node"] as EmissionPhase).coast_speed > 0.0
	fields.append(coast)
	var defaults: Dictionary = _phase_defaults()
	for spec: Array in [
		["gravity", "gravity", "gravity_mps2", "u/s²"],
		["launch pitch", "launch_pitch", "launch_pitch_degrees", "°"],
		["steering", "turn_rate", "turn_rate_degrees_per_second", "°/s"],
		["launch speed ratio", "launch_speed_ratio", "launch_speed_ratio", ""],
		["acceleration", "acceleration", "acceleration_mps2", "u/s²"],
		["minimum speed", "min_speed", "min_speed", "u/s"],
		["turn bleed", "turn_bleed", "turn_bleed_mps2_per_radian", "u/s² per rad"],
		["lead", "lead", "lead_fraction", ""],
		["lock cone", "lock_cone", "lock_cone_degrees", "°"],
		["lock range", "lock_range", "lock_range", "u"],
		["motor burn", "burn", "burn_seconds", "s"],
		["jitter", "jitter", "jitter_degrees", "°"],
		["jitter frequency", "jitter_frequency", "jitter_frequency_hz", "Hz"],
	]:
		var field := _field(
			&"weapon",
			PieceField.Scope.PHASE,
			spec[0],
			["motion", spec[1]],
			PieceField.Kind.NUMBER,
			PieceField.Tier.VERBOSE
		)
		field.unit = spec[3]
		var property: String = spec[2]
		var default: float = defaults[property]
		field.read = func(c: Dictionary) -> Variant: return c["node"].get(property)
		field.applies = func(c: Dictionary) -> bool:
			return not is_equal_approx(float(c["node"].get(property)), default)
		fields.append(field)
	var arrival := _field(
		&"weapon",
		PieceField.Scope.PHASE,
		"ends on arrival",
		["ends_on_arrival"],
		PieceField.Kind.BOOL,
		PieceField.Tier.VERBOSE
	)
	arrival.read = func(c: Dictionary) -> Variant:
		return (c["node"] as EmissionPhase).ends_on_arrival
	fields.append(arrival)
	var lifespan := _field(
		&"weapon",
		PieceField.Scope.PHASE,
		"ends after",
		["lifespan"],
		PieceField.Kind.NUMBER,
		PieceField.Tier.VERBOSE
	)
	lifespan.unit = "s"
	lifespan.read = func(c: Dictionary) -> Variant:
		return (c["node"] as EmissionPhase).lifespan_seconds
	fields.append(lifespan)
	var impact := _field(
		&"weapon",
		PieceField.Scope.PHASE,
		"ends on striking",
		["impact_mask"],
		PieceField.Kind.FLAGS,
		PieceField.Tier.VERBOSE
	)
	impact.options = IMPACT_LAYERS
	impact.read = func(c: Dictionary) -> Variant: return (c["node"] as EmissionPhase).impact_mask
	fields.append(impact)
	var payload := _field(
		&"weapon",
		PieceField.Scope.PHASE,
		"applies payload",
		["payload"],
		PieceField.Kind.CADENCE,
		PieceField.Tier.VERBOSE
	)
	payload.unit = "s"
	payload.read = func(c: Dictionary) -> Variant:
		var phase: EmissionPhase = c["node"]
		return phase.payload_period_seconds if phase.applies_payload else null
	fields.append(payload)
	return fields


static func _pool_fields() -> Array:
	var fields: Array = []
	for spec: Array in [
		["charges", "max_charges", PieceField.Kind.INTEGER, ""],
		["starting charges", "initial_charges", PieceField.Kind.INTEGER, ""],
		["cooldown", "cooldown", PieceField.Kind.NUMBER, "s"],
	]:
		var field := _field(
			&"name", PieceField.Scope.POOL, spec[0], [spec[1]], spec[2], PieceField.Tier.VERBOSE
		)
		field.unit = spec[3]
		field.is_ticks = spec[1] == "cooldown"
		var key: String = spec[1]
		field.read = func(c: Dictionary) -> Variant:
			return (c["node"] as Abilities).pool_value(int(c["index"]), key)
		field.write = func(c: Dictionary, _old: Variant, new: Variant) -> void:
			(c["node"] as Abilities).retune_pool(int(c["index"]), key, int(new))
		fields.append(field)
	return fields


#endregion


#region Builders
static func _field(
	a_widget: StringName,
	a_scope: PieceField.Scope,
	a_label: String,
	a_path: Array,
	a_kind: PieceField.Kind,
	a_tier: PieceField.Tier
) -> PieceField:
	var field := PieceField.new()
	field.widget = a_widget
	field.scope = a_scope
	field.label = a_label
	field.doc_path = a_path
	field.kind = a_kind
	field.tier = a_tier
	return field


## A PIECE field that is one property of one component, written straight through.
static func _property(
	a_widget: StringName,
	a_label: String,
	a_path: Array,
	a_kind: PieceField.Kind,
	a_node: String,
	a_property: String,
	a_options: Variant = null
) -> PieceField:
	var field := _field(
		a_widget, PieceField.Scope.PIECE, a_label, a_path, a_kind, PieceField.Tier.VERBOSE
	)
	field.options = a_options
	field.read = func(c: Dictionary) -> Variant:
		var node: Node = _node(c, a_node)
		return node.get(a_property) if node != null else null
	field.write = func(c: Dictionary, _old: Variant, new: Variant) -> void:
		var node: Node = _node(c, a_node)
		if node != null:
			node.set(a_property, new)
	field.applies = func(c: Dictionary) -> bool: return _node(c, a_node) != null
	return field


## A PIECE field naming a library shape on one of the root's volumes.
static func _shape(
	a_widget: StringName,
	a_label: String,
	a_path: Array,
	a_node: String,
	a_prefix: String,
	a_tier: PieceField.Tier
) -> PieceField:
	var field := _field(
		a_widget, PieceField.Scope.PIECE, a_label, a_path, PieceField.Kind.SHAPE, a_tier
	)
	field.unit = "u"
	field.options = [a_prefix]
	field.read = func(c: Dictionary) -> Variant:
		var node: CollisionShape3D = _node(c, a_node) as CollisionShape3D
		return node.shape if node != null else null
	field.write = func(c: Dictionary, _old: Variant, new: Variant) -> void:
		var node: CollisionShape3D = _node(c, a_node) as CollisionShape3D
		if node != null:
			node.shape = new
	field.shape_node = func(c: Dictionary) -> CollisionShape3D:
		return _node(c, a_node) as CollisionShape3D
	return field


## A physical body's radius: saved, applied only by the importer (debug-tuning.md §An edit is
## to the piece TYPE).
static func _body_radius(
	a_widget: StringName, a_label: String, a_key: String, a_node: String
) -> PieceField:
	var field := _field(
		a_widget,
		PieceField.Scope.PIECE,
		a_label,
		["body", a_key],
		PieceField.Kind.NUMBER,
		PieceField.Tier.VERBOSE
	)
	field.unit = "u"
	field.is_live = false
	field.read = func(c: Dictionary) -> Variant:
		var node: CollisionShape3D = _node(c, a_node) as CollisionShape3D
		return RangeShapes.radius_of(node.shape) if node != null and node.shape != null else null
	field.applies = func(c: Dictionary) -> bool: return _node(c, a_node) != null
	field.shape_node = func(c: Dictionary) -> CollisionShape3D:
		return _node(c, a_node) as CollisionShape3D
	return field


static func _preset_enum() -> Dictionary:
	var presets: Dictionary = {}
	for name: String in EmissionPhase.PRESETS:
		presets[name] = presets.size()
	return presets


static func _phase_defaults() -> Dictionary:
	var phase := EmissionPhase.new()
	var defaults: Dictionary = {}
	for property: Dictionary in phase.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and property["type"] == TYPE_FLOAT:
			defaults[property["name"]] = phase.get(property["name"])
	phase.free()
	return defaults


#endregion


#region Reading the piece
static func _node(a_ctx: Dictionary, a_path: String) -> Node:
	var root: Node = a_ctx["node"]
	return root.get_node_or_null(a_path) if root != null else null


static func _defense(a_ctx: Dictionary) -> Defense:
	return _node(a_ctx, "Defense") as Defense


static func _movement(a_ctx: Dictionary) -> Movement:
	return _node(a_ctx, "Locomotion") as Movement


## The doc's hp, not the upgraded maximum: what tuning edits is what Save writes back.
static func _authored_hp(a_ctx: Dictionary) -> Variant:
	var defense: Defense = _defense(a_ctx)
	return defense.authored_hp_max() if defense != null else null


## A maximum keeps the fraction: a unit at half health stays at half.
static func _retune_hp(a_ctx: Dictionary, _a_old: Variant, a_new: Variant) -> void:
	var defense: Defense = _defense(a_ctx)
	var fraction: float = defense.hp / defense.hp_max if defense.hp_max > 0.0 else 1.0
	defense.set_authored_hp_max(float(a_new))
	if defense.is_node_ready():
		defense.hp = fraction * defense.hp_max
		defense.hp_changed.emit(defense.hp, defense.hp_max)


## A speed held down by a slow keeps its slow: the live value is scaled by what changed.
## Whether the piece carries a weapon measuring reach from its orbit (Weapon.RangeOrigin.ORBIT).
static func _has_orbit_weapon(a_ctx: Dictionary) -> bool:
	var loadout: Node = _node(a_ctx, "Loadout")
	if loadout == null:
		return false
	for child: Node in loadout.get_children():
		if child is Weapon and (child as Weapon).range_origin == Weapon.RangeOrigin.ORBIT:
			return true
	return false


static func _retune_speed(a_ctx: Dictionary, a_old: Variant, a_new: Variant) -> void:
	var movement: Movement = _movement(a_ctx)
	var old: float = float(a_old) if a_old != null else 0.0
	movement.speed = movement.speed * float(a_new) / old if old > 0.0 else float(a_new)


## Re-derive a piece's aggro from its reach. A piece not yet in play derives it in _ready.
static func _refresh_reach(a_piece: Variant) -> void:
	if a_piece is Entity and (a_piece as Entity).is_node_ready():
		(a_piece as Entity).refresh_aggro_shapes()


#endregion


#region Conversions
## The doc value a raw runtime value is written as. `a_speeds` is the speed ladder
## {class: u/s}, for a SPEED_CLASS — a speed matching no class is written as its number, which
## the importer refuses, so it shows as a doc error rather than as a silent guess.
static func to_doc(a_field: PieceField, a_raw: Variant, a_speeds: Dictionary = {}) -> Variant:
	if a_raw == null:
		return null
	match a_field.kind:
		PieceField.Kind.NUMBER:
			if a_field.is_ticks:
				return TimeUtils.seconds_from_ticks(int(a_raw))
			return float(a_raw)
		PieceField.Kind.INTEGER:
			if a_field.is_ticks:
				return TimeUtils.seconds_from_ticks(int(a_raw))
			return int(a_raw)
		PieceField.Kind.ENUM:
			return enum_name(a_field.options, int(a_raw))
		PieceField.Kind.FLAGS:
			return flag_names(a_field.options, int(a_raw))
		PieceField.Kind.SPEED_CLASS:
			for name: String in a_speeds:
				if is_equal_approx(float(a_speeds[name]), float(a_raw)):
					return name
			return float(a_raw)
		PieceField.Kind.SHAPE:
			# A piece-local volume is no library shape, so the doc names none.
			var id: String = shape_id(a_raw)
			return id if not id.is_empty() else null
		PieceField.Kind.CADENCE:
			return "once" if is_inf(float(a_raw)) else float(a_raw)
		PieceField.Kind.ID_LIST:
			return (a_raw as Array).duplicate()
	return a_raw


## The raw runtime value a doc value stands for. `a_speeds` as in to_doc.
static func from_doc(a_field: PieceField, a_doc: Variant, a_speeds: Dictionary = {}) -> Variant:
	if a_doc == null:
		return null
	match a_field.kind:
		PieceField.Kind.NUMBER:
			return TimeUtils.ticks_from_seconds(float(a_doc)) if a_field.is_ticks else float(a_doc)
		PieceField.Kind.INTEGER:
			return TimeUtils.ticks_from_seconds(float(a_doc)) if a_field.is_ticks else int(a_doc)
		PieceField.Kind.BOOL:
			return bool(a_doc)
		PieceField.Kind.ENUM:
			return int((a_field.options as Dictionary).get(str(a_doc), 0))
		PieceField.Kind.FLAGS:
			var mask: int = 0
			for name: Variant in a_doc:
				mask |= int((a_field.options as Dictionary).get(str(name), 0))
			return mask
		PieceField.Kind.SPEED_CLASS:
			if a_doc is float or a_doc is int:
				return float(a_doc)
			return float(a_speeds.get(str(a_doc), 0.0))
		PieceField.Kind.SHAPE:
			return shape_resource(str(a_doc))
		PieceField.Kind.SHAPE_PAIR:
			if not (a_doc is Dictionary):
				return 0.0
			var from: float = RangeShapes.radius_of(shape_resource(str(a_doc.get("from", ""))))
			var to: float = RangeShapes.radius_of(shape_resource(str(a_doc.get("to", ""))))
			return maxf(to - from, 0.0)
		PieceField.Kind.CADENCE:
			return INF if str(a_doc) == "once" else float(a_doc)
		PieceField.Kind.ID_LIST:
			return (a_doc as Array).map(func(id: Variant) -> String: return str(id))
	return a_doc


## What a person reads for a raw value: a figure with its unit, a name, a list.
static func display(a_field: PieceField, a_raw: Variant) -> String:
	if a_raw == null:
		return "none"
	match a_field.kind:
		PieceField.Kind.NUMBER, PieceField.Kind.INTEGER:
			var value: float = (
				TimeUtils.seconds_from_ticks(int(a_raw)) if a_field.is_ticks else float(a_raw)
			)
			if is_inf(value):
				return "unbounded"
			return _with_unit(_figure(value), a_field.unit)
		PieceField.Kind.BOOL:
			return "yes" if a_raw else "no"
		PieceField.Kind.ENUM:
			return enum_name(a_field.options, int(a_raw)).to_lower().replace("_", " ")
		PieceField.Kind.FLAGS:
			var names: Array = flag_names(a_field.options, int(a_raw))
			return ", ".join(names).to_lower() if not names.is_empty() else "none"
		PieceField.Kind.SPEED_CLASS:
			return _with_unit(_figure(float(a_raw)), a_field.unit)
		PieceField.Kind.SHAPE:
			var radius: float = RangeShapes.radius_of(a_raw)
			return _with_unit(_figure(radius), a_field.unit) if radius >= 0.0 else "none"
		PieceField.Kind.SHAPE_PAIR:
			return "+" + _with_unit(_figure(float(a_raw)), a_field.unit)
		PieceField.Kind.CADENCE:
			return (
				"once"
				if is_inf(float(a_raw))
				else "every %s" % _with_unit(_figure(float(a_raw)), "s")
			)
		PieceField.Kind.ID_LIST:
			var names: Array = (a_raw as Array).map(
				func(id: Variant) -> String: return str(id).replace("_", " ")
			)
			return ", ".join(names) if not names.is_empty() else "none"
	return str(a_raw)


## Every status effect an emission may list: the generated StatusEffectIds, by value.
static func status_effect_ids() -> Array:
	var ids: Array = []
	for value: Variant in load(STATUS_EFFECT_IDS).get_script_constant_map().values():
		ids.append(str(value))
	ids.sort()
	return ids


## The status effects an emission applies, by id: each effect scene under its EffectApplicator
## is named for the effect (the importer instances `<id>.tscn`).
static func applied_effects(a_emission: Node) -> Array:
	var ids: Array = []
	var applicator: Node = a_emission.get_node_or_null("EffectApplicator")
	if applicator == null:
		return ids
	for child: Node in applicator.get_children():
		if child is StatusEffect and not child.scene_file_path.is_empty():
			ids.append(child.scene_file_path.get_file().get_basename())
	return ids


static func enum_name(a_enum: Dictionary, a_value: int) -> String:
	for key: String in a_enum:
		if int(a_enum[key]) == a_value:
			return key
	return "?"


static func flag_names(a_bits: Dictionary, a_mask: int) -> Array:
	var names: Array = []
	for name: String in a_bits:
		if a_mask & int(a_bits[name]):
			names.append(name)
	return names


## A library shape's id — the name of the generated file it was loaded from — or "" for a
## shape that is not one (a piece-local cylinder).
static func shape_id(a_shape: Variant) -> String:
	if not (a_shape is Shape3D):
		return ""
	var path: String = (a_shape as Shape3D).resource_path
	return path.get_file().get_basename() if path.begins_with(SHAPES_DIR) else ""


static func shape_resource(a_id: String) -> Shape3D:
	if a_id.is_empty():
		return null
	var path: String = SHAPES_DIR + a_id + SHAPE_EXTENSION
	return load(path) as Shape3D if ResourceLoader.exists(path) else null


## A figure to the precision a tuning value means: whole numbers bare, the rest to two places.
static func _figure(a_value: float) -> String:
	if is_equal_approx(a_value, roundf(a_value)):
		return str(int(roundf(a_value)))
	return String.num(a_value, 2)


static func _with_unit(a_figure: String, a_unit: String) -> String:
	if a_unit.is_empty():
		return a_figure
	return a_figure + (a_unit if a_unit in ["s", "°", "°/s"] else " " + a_unit)
#endregion
