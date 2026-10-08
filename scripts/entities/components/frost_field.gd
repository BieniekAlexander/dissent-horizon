class_name FrostField
extends Node

## A lingering area that freezes the units standing in it: the Avalanche's shot and the
## Blizzard. A component on an EMISSION, active only during the emission's LAST phase — the
## field itself; any earlier phase is the flight there, or the storm gathering. Its volume is
## the emission's HitShape. Rules: gdd/systems/combat/shields.md §Frost fields.
##
## EXPOSURE: a unit must stand in the field for `exposure_seconds` before it freezes. Time in
## the field builds exposure a tick at a time; time out of it drains exposure back at the same
## rate, so a unit cannot dash through in short hops. Once frozen, the field HOLDS the freeze at
## full time for as long as the unit stays in it, but never mends its ice: a freeze broken by
## damage inside the field starts that unit's exposure over.

## Seconds a unit must spend in the field before it freezes.
@export var exposure_seconds: float = 2.0
## The freeze the field applies. One authored freeze, shared with the Freeze sanction.
@export var freeze_effect: PackedScene = preload("res://scenes/entities/status_effects/freeze.tscn")
## Most units one field can weigh in a tick; a query cap, not a design limit.
@export var max_victims: int = 64

## Unit instance id -> ticks of exposure, capped at the threshold.
var _exposure: Dictionary = {}
## Unit instance id -> true for the units this field has frozen and is holding.
var _held: Dictionary = {}
## The instance id of the piece that fired this field, credited with its freezes; 0 for none
## (a Blizzard). An id rather than a reference because the source may die before the field.
var _source_id: int = 0


func _ready() -> void:
	var phased: PhasedLocomotion = _phased()
	if phased != null:
		phased.phase_ticking.connect(_on_phase_ticking)


func host() -> Entity:
	return get_parent() as Entity


## Ticks of exposure that freeze a unit.
func threshold_ticks() -> int:
	return maxi(1, TimeUtils.ticks_from_seconds(exposure_seconds))


## How much exposure `a_unit` has built in this field, in ticks.
func exposure_of(a_unit: Entity) -> int:
	return int(_exposure.get(a_unit.get_instance_id(), 0))


#region Ticking
func _on_phase_ticking(_a_phase: EmissionPhase) -> void:
	var phased: PhasedLocomotion = _phased()
	if phased.phase_index() == 0 and phased.phase_ticks() == 0:
		_source_id = _source_of_shot()
	if phased.phase_index() == phased.phase_count() - 1:
		tick_exposure(_units_inside())


## One tick of exposure, given the units standing in the field now. Public so a test can
## drive it without a physics world.
func tick_exposure(a_inside: Array[Actor]) -> void:
	var threshold: int = threshold_ticks()
	var inside_ids: Dictionary = {}
	for unit: Actor in a_inside:
		var id: int = unit.get_instance_id()
		inside_ids[id] = unit
		_exposure[id] = mini(int(_exposure.get(id, 0)) + 1, threshold)
	for id: int in _exposure.keys():
		if inside_ids.has(id):
			continue
		_exposure[id] = int(_exposure[id]) - 1
		if int(_exposure[id]) <= 0:
			_exposure.erase(id)
			_held.erase(id)
	for id: int in inside_ids:
		if int(_exposure[id]) >= threshold:
			_hold_freeze(inside_ids[id], id)


## Freeze `a_unit`, or keep its freeze at full time. A freeze this field was holding that is
## gone while the unit still stands here was broken, so the unit's exposure starts over.
func _hold_freeze(a_unit: Actor, a_id: int) -> void:
	var freeze: FreezeStatusEffect = _freeze_on(a_unit)
	if freeze != null:
		freeze.hold_for(_freeze_ticks())
		_held[a_id] = true
		return
	if _held.has(a_id):
		_held.erase(a_id)
		_exposure[a_id] = 0
		return
	var effect: FreezeStatusEffect = freeze_effect.instantiate() as FreezeStatusEffect
	var source: Variant = instance_from_id(_source_id) if _source_id != 0 else null
	effect.apply_to(a_unit, source as Actor if is_instance_valid(source) else null)
	if effect.is_active():
		_held[a_id] = true


#endregion


#region Source
## The instance id of the piece that fired this field, read off its Payload, or 0.
func _source_of_shot() -> int:
	var payload: Payload = Payload.of(host())
	var from: Variant = payload.from if payload != null else null
	return (from as Object).get_instance_id() if is_instance_valid(from) else 0


#endregion


#region Helpers
func _phased() -> PhasedLocomotion:
	return host().get_node_or_null("Locomotion") as PhasedLocomotion


## The full time a freeze lasts, which the field holds a frozen unit at.
func _freeze_ticks() -> int:
	return FreezeStatusEffect.freeze_ticks()


static func _freeze_on(a_unit: Actor) -> FreezeStatusEffect:
	for child: Node in a_unit.get_children():
		if child is FreezeStatusEffect and (child as FreezeStatusEffect).is_active():
			return child as FreezeStatusEffect
	return null


## The units in the field's volume that a freeze would take: structures and STRONG pieces
## are never frozen by a field.
func _units_inside() -> Array[Actor]:
	var shape: CollisionShape3D = host().get_node_or_null("HitShape") as CollisionShape3D
	var units: Array[Actor] = []
	if shape == null or shape.shape == null:
		return units
	# Upright, whatever the emission's last heading, as a blast is (Payload._blast_victims).
	var xform: Transform3D = shape.global_transform
	xform.basis = Basis.from_scale(xform.basis.get_scale())
	for entity: Entity in SU.query_shape_for_entities(
		host().get_world_3d(),
		shape.shape,
		xform,
		CollisionLayers.TARGETABLE_ANY,
		[host()],
		max_victims
	):
		var unit := entity as Actor
		if unit != null and unit.is_in_group("unit") and FreezeStatusEffect.can_freeze(unit):
			units.append(unit)
	return units
#endregion
