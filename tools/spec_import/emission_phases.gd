extends RefCounted

## An emission doc's PHASES: the `phases:` list, or the flat shorthand that stands for the
## common two-phase shape when the list is absent. Pure — no scene, no registry — so the doc
## grammar is testable on dictionaries alone. SpecRegistry validates through `errors_for`,
## SpecSceneSync writes what `expand` returns.
##
## The grammar is gdd/systems/combat/projectiles.md §Phases.

const EmissionPhaseScript := preload("res://scripts/entities/tools/emission_phase.gd")

## Keys a `phases:` item may carry.
const PHASE_KEYS: Array[String] = [
	"name", "motion", "ends_on_arrival", "lifespan", "impact_mask", "payload", "emits", "visuals"
]
## Keys a `motion:` mapping may carry, and the EmissionPhase property each one writes.
const MOTION_PROPERTIES: Dictionary = {
	"speed": "speed",
	"gravity": "gravity_mps2",
	"launch_pitch": "launch_pitch_degrees",
	"turn_rate": "turn_rate_degrees_per_second",
	"launch_speed_ratio": "launch_speed_ratio",
	"acceleration": "acceleration_mps2",
	"min_speed": "min_speed",
	"jitter": "jitter_degrees",
	"jitter_frequency": "jitter_frequency_hz",
	"burn": "burn_seconds",
	"coast_speed": "coast_speed",
	"turn_bleed": "turn_bleed_mps2_per_radian",
	"lead": "lead_fraction",
	"lock_cone": "lock_cone_degrees",
	"lock_range": "lock_range",
}
## `impact_mask:` names, and the collision layer each one stands for.
const IMPACT_LAYERS: Dictionary = {
	"terrain": CollisionLayers.Mask.TERRAIN,
	"structures": CollisionLayers.Mask.STRUCTURE_BLOCKER,
	"ground": CollisionLayers.Mask.TARGETABLE_GROUND,
	"air": CollisionLayers.Mask.TARGETABLE_AIR,
}
## The flat shorthand's motion when a doc names no `trajectory:` — what the enum defaulted to.
const DEFAULT_PRESET: String = "BALLISTIC"
## Visual nodes a phase shows when its item names none: the first phase and any later phase
## that moves the in-flight set (a later moving phase is the same flight's next stage), every
## other the post-impact set. Only those present in the scene are written.
const IN_FLIGHT_VISUALS: Array[String] = ["InFlightSprite", "InFlightParticles", "InFlightMesh"]
const POST_IMPACT_VISUALS: Array[String] = [
	"PostImpactSprite", "PostImpactParticles", "PostImpactMesh"
]
## Scene-node names for phases whose item names none.
const DEFAULT_NAMES: Array[String] = ["Flight", "Impact"]


## The doc's phases as EmissionPhase property sets, in run order. Each entry also carries
## `name`, `visual_roles` (candidate node names) and `emits` (an emission id, or "").
## Assumes `errors_for(spec)` is empty.
static func expand(spec: Dictionary) -> Array[Dictionary]:
	var items: Array = spec["phases"] if spec.has("phases") else _shorthand_items(spec)
	var phases: Array[Dictionary] = []
	for i: int in items.size():
		phases.append(_expand_item(items[i], i))
	return phases


## Every authoring error in the doc's phase grammar, as sentences.
static func errors_for(spec: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if spec.has("phases"):
		for flat: String in ["speed", "trajectory"]:
			if spec.has(flat):
				errors.append("%s: beside phases: — move it into the first phase's motion:" % flat)
		if not (spec["phases"] is Array) or (spec["phases"] as Array).is_empty():
			errors.append("phases: must be a non-empty list")
			return errors
		for i: int in (spec["phases"] as Array).size():
			errors.append_array(_item_errors(spec["phases"][i], i))
		return errors
	if spec.has("trajectory") and not EmissionPhaseScript.PRESETS.has(str(spec["trajectory"])):
		errors.append(
			(
				"trajectory '%s' is not one of %s"
				% [spec["trajectory"], ", ".join(EmissionPhaseScript.PRESETS.keys())]
			)
		)
	elif _is_steered(_preset(str(spec.get("trajectory", DEFAULT_PRESET)))):
		errors.append(
			(
				"trajectory %s steers, so its flight needs a lifespan: — write phases:"
				% spec["trajectory"]
			)
		)
	return errors


## The motion scalars of the doc's FIRST phase — what classifies its placeholder model.
static func first_motion(spec: Dictionary) -> Dictionary:
	return expand(spec)[0]


## The emission ids named by any phase's `emits:`, for cross-reference validation.
static func emitted_ids(spec: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	if spec.get("phases") is Array:
		for item: Variant in spec["phases"]:
			if item is Dictionary and (item as Dictionary).get("emits") is Dictionary:
				ids.append(str(item["emits"].get("id", "")))
	return ids


static func _shorthand_items(spec: Dictionary) -> Array:
	var motion: Dictionary = {"preset": str(spec.get("trajectory", DEFAULT_PRESET))}
	if spec.has("speed"):
		motion["speed"] = spec["speed"]
	return [
		{"motion": motion},
		{"lifespan": 0, "payload": "once"},
	]


static func _expand_item(item: Dictionary, index: int) -> Dictionary:
	var has_motion: bool = item.has("motion")
	var phase: Dictionary = _motion_properties(item.get("motion", {}))
	phase["name"] = str(
		item.get(
			"name", DEFAULT_NAMES[index] if index < DEFAULT_NAMES.size() else "Phase%d" % index
		)
	)
	phase["ends_on_arrival"] = bool(item.get("ends_on_arrival", has_motion))
	phase["lifespan_seconds"] = float(item["lifespan"]) if item.has("lifespan") else INF
	phase["impact_mask"] = _impact_mask(item.get("impact_mask", []))
	phase["applies_payload"] = item.has("payload")
	phase["payload_period_seconds"] = _period(item.get("payload", "once"))
	var emits: Dictionary = item.get("emits", {})
	phase["emits"] = str(emits.get("id", ""))
	phase["event_period_seconds"] = _period(emits.get("every", "once"))
	var moves: bool = phase["speed"] > 0.0 or phase["gravity_mps2"] > 0.0
	phase["visual_roles"] = (
		item["visuals"]
		if item.has("visuals")
		else (IN_FLIGHT_VISUALS if index == 0 or moves else POST_IMPACT_VISUALS)
	)
	return phase


## A motion (a preset name, or a mapping with an optional `preset:`) as the EmissionPhase
## motion properties, every one written out so the scene states the whole motion.
static func _motion_properties(motion: Variant) -> Dictionary:
	var mapping: Dictionary = {"preset": motion} if motion is String else motion
	var values: Dictionary = _preset(str(mapping.get("preset", "LINEAR"))).duplicate()
	for key: String in MOTION_PROPERTIES:
		if mapping.has(key):
			values[key] = mapping[key]
	var properties: Dictionary = {}
	var defaults: EmissionPhase = EmissionPhaseScript.new()
	for key: String in MOTION_PROPERTIES:
		var property: String = MOTION_PROPERTIES[key]
		properties[property] = float(values.get(key, defaults.get(property)))
	defaults.free()
	return properties


static func _preset(preset_name: String) -> Dictionary:
	return EmissionPhaseScript.PRESETS.get(preset_name, {})


static func _is_steered(motion: Dictionary) -> bool:
	return float(motion.get("turn_rate", 0.0)) > 0.0


static func _impact_mask(names: Array) -> int:
	var mask: int = 0
	for layer_name: Variant in names:
		mask |= int(IMPACT_LAYERS.get(str(layer_name), 0))
	return mask


## A cadence: `once`, or seconds between applications (0 is every tick).
static func _period(value: Variant) -> float:
	return INF if str(value) == "once" else float(value)


static func _item_errors(item: Variant, index: int) -> Array[String]:
	var where: String = "phases[%d]" % index
	if not (item is Dictionary):
		return ["%s: must be a mapping" % where]
	var errors: Array[String] = []
	for key: Variant in item:
		if not PHASE_KEYS.has(str(key)):
			errors.append("%s: unknown key '%s' (one of %s)" % [where, key, ", ".join(PHASE_KEYS)])
	errors.append_array(_motion_errors(item.get("motion", {}), where))
	var motion: Dictionary = (
		_motion_properties(item.get("motion", {}))
		if _motion_errors(item.get("motion", {}), where).is_empty()
		else {}
	)
	var steers: bool = float(motion.get("turn_rate_degrees_per_second", 0.0)) > 0.0
	if steers and not item.has("lifespan"):
		errors.append(
			"%s: a steered motion needs a lifespan:, or a lost target flies forever" % where
		)
	for steering_key: String in ["turn_bleed", "lead", "lock_cone", "lock_range"]:
		var property: String = MOTION_PROPERTIES[steering_key]
		if float(motion.get(property, 0.0)) > 0.0 and not steers:
			errors.append(
				"%s: %s acts while steering — it needs a turn_rate" % [where, steering_key]
			)
	if float(motion.get("lead_fraction", 0.0)) > 1.0:
		errors.append("%s: lead is a fraction of the target's predicted motion, 0 to 1" % where)
	var burns: bool = float(motion.get("burn_seconds", 0.0)) > 0.0
	if float(motion.get("lock_cone_degrees", 0.0)) > 180.0:
		errors.append("%s: lock_cone is degrees off the nose, at most 180" % where)
	var coasts: bool = float(motion.get("coast_speed", 0.0)) > 0.0
	if burns != coasts:
		errors.append(
			"%s: burn and coast_speed come as a pair — a burn-out needs a speed to coast at" % where
		)
	elif burns and float(motion.get("gravity_mps2", 0.0)) > 0.0:
		errors.append(
			"%s: a falling motion cannot burn out — its speed is solved from the arc" % where
		)
	if (
		float(motion.get("launch_pitch_degrees", 0.0)) > 0.0
		and float(motion.get("gravity_mps2", 0.0)) <= 0.0
	):
		errors.append("%s: launch_pitch without gravity has no arc to pitch" % where)
	if item.has("lifespan") and not _is_non_negative_number(item["lifespan"]):
		errors.append("%s: lifespan must be a number of seconds, 0 or more" % where)
	for layer_name: Variant in item.get("impact_mask", []):
		if not IMPACT_LAYERS.has(str(layer_name)):
			errors.append(
				(
					"%s: impact_mask '%s' is not one of %s"
					% [where, layer_name, ", ".join(IMPACT_LAYERS.keys())]
				)
			)
	if item.has("payload") and not _is_cadence(item["payload"]):
		errors.append("%s: payload must be `once` or seconds between applications" % where)
	if item.has("emits"):
		var emits: Variant = item["emits"]
		if not (emits is Dictionary) or not (emits as Dictionary).has("id"):
			errors.append("%s: emits: needs an id:" % where)
		elif (emits as Dictionary).has("every") and not _is_cadence(emits["every"]):
			errors.append("%s: emits.every must be `once` or seconds" % where)
	return errors


static func _motion_errors(motion: Variant, where: String) -> Array[String]:
	if motion is String:
		return (
			[]
			if EmissionPhaseScript.PRESETS.has(motion)
			else ["%s: motion '%s' is not a preset" % [where, motion]]
		)
	if not (motion is Dictionary):
		return ["%s: motion must be a preset name or a mapping" % where]
	var errors: Array[String] = []
	for key: Variant in motion:
		if str(key) == "preset":
			if not EmissionPhaseScript.PRESETS.has(str(motion[key])):
				errors.append("%s: motion preset '%s' is not a preset" % [where, motion[key]])
		elif not MOTION_PROPERTIES.has(str(key)):
			errors.append("%s: unknown motion key '%s'" % [where, key])
		elif not _is_non_negative_number(motion[key]):
			errors.append("%s: motion %s must be a number, 0 or more" % [where, key])
	return errors


static func _is_non_negative_number(value: Variant) -> bool:
	return (value is int or value is float) and float(value) >= 0.0


static func _is_cadence(value: Variant) -> bool:
	return str(value) == "once" or _is_non_negative_number(value)
