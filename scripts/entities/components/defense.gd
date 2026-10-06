class_name Defense
extends Node

#region Properties
enum ArmourType { LIGHT = 0, MEDIUM = 1, STRONG = 2 }
enum FrameType { BIO = 0, MECH = 1 }

@export var armour_type: ArmourType = ArmourType.LIGHT
@export var frame_type: FrameType = FrameType.BIO
@export var hp_max: float = 100
var hp: float

## Emitted whenever hp changes, so visuals (the HP bar) can update reactively
## instead of polling hp every frame. Carries the new hp and hp_max.
signal hp_changed(hp: float, hp_max: float)

## Emitted when damage empties a shield, which leaves the piece at once. Whatever granted it
## (a Freeze) listens, since a broken shield ends what it was part of.
signal shield_broken(type: Shield.Type)

## What owned upgrades multiply the authored hp_max by (UpgradeCatalog.HP_FACTOR). Stored rather
## than asked for per read because hp_max is read in some sixty places; Commandable keeps it in
## step with its commander's upgrades (_apply_upgrades).
var _hp_factor: float = 1.0

## The shields standing over this Defense, Shield.Type -> Shield, at most one per type. Damage
## meets them in type order before it reaches hp. See gdd/systems/combat/shields.md.
var _shields: Dictionary = {}
#endregion


#region Lifecycle
func _ready() -> void:
	hp = hp_max


#endregion


#region Upgrades
## hp_max as the doc authors it, before any upgrade.
func authored_hp_max() -> float:
	return hp_max / _hp_factor


## Scale hp_max to `a_factor` times the authored value, keeping the FRACTION of health: a unit
## at 60 of 100 that gains a quarter goes to 75 of 125, and one captured by a commander without
## the upgrade comes back down the same way. Before _ready the live hp is not set yet, and _ready
## fills it to the new maximum.
func set_hp_factor(a_factor: float) -> void:
	if is_equal_approx(a_factor, _hp_factor) or a_factor <= 0.0:
		return
	var ratio: float = a_factor / _hp_factor
	hp_max *= ratio
	_hp_factor = a_factor
	if not is_node_ready() or hp <= 0.0:
		return
	hp *= ratio
	hp_changed.emit(hp, hp_max)


## Set the authored maximum (debug tuning), keeping whatever upgrade factor is in force.
func set_authored_hp_max(a_value: float) -> void:
	hp_max = a_value * _hp_factor


#endregion


#region Shields
## Stand `a_shield` over this Defense. A shield of the same type already standing keeps the
## larger hit points of the two rather than gaining a second layer.
func apply_shield(a_shield: Shield) -> void:
	var standing: Shield = _shields.get(a_shield.type)
	if standing == null:
		_shields[a_shield.type] = a_shield
		return
	standing.hp = maxf(standing.hp, a_shield.hp)


func remove_shield(a_type: Shield.Type) -> void:
	_shields.erase(a_type)


## The shield of `a_type` standing over this Defense, or null when there is none.
func shield_of(a_type: Shield.Type) -> Shield:
	return _shields.get(a_type)


## Total hit points across every standing shield.
func shield_hp() -> float:
	var total: float = 0.0
	for shield: Shield in _shields.values():
		total += shield.hp
	return total


#endregion


#region Mutators
## Deal `a_base` damage of `a_damage_type`: through each shield in type order, then to hp.
## Each layer resists with its own armour and frame. What a layer cannot hold passes on as the
## BASE damage it did not absorb, so the next layer applies its own multipliers to it rather
## than inheriting the last one's. Returns the damage actually dealt, across every layer.
func take_damage(a_base: float, a_damage_type: Damage.Type) -> float:
	var remaining: float = a_base
	var dealt: float = 0.0
	var types: Array = _shields.keys()
	types.sort()
	for type: Shield.Type in types:
		var shield: Shield = _shields[type]
		var factor: float = DamageTable.multiplier(
			a_damage_type, shield.armour_over(self), shield.frame_over(self)
		)
		if factor <= 0.0:
			continue  # this layer is immune, so it passes everything on untouched
		var effective: float = remaining * factor
		if effective < shield.hp:
			shield.hp -= effective
			return dealt + effective
		dealt += shield.hp
		remaining -= shield.hp / factor
		shield.hp = 0.0
		_shields.erase(type)
		shield_broken.emit(type)
	var final_amount: float = (
		remaining * DamageTable.multiplier(a_damage_type, armour_type, frame_type)
	)
	apply_damage(final_amount)
	return dealt + final_amount


## Lower hp by `amount` (already armour-adjusted by the caller), bypassing any shield.
## Returns true when this brought a previously-living entity to 0 or below — i.e. the hit
## was lethal — so the caller can run death-attribution logic. Death handling itself stays with
## the caller (Commandable._update_state detects hp <= 0).
func apply_damage(a_amount: float) -> bool:
	var was_alive: bool = hp > 0
	hp -= a_amount
	hp_changed.emit(hp, hp_max)
	return was_alive and hp <= 0


## Raise hp by `amount`, never past hp_max. Returns true once the entity is at FULL
## health, so a mender (the Repair command, a heal aura) can stop on the tick it finishes
## rather than polling hp itself. A no-op call — already full, or a non-positive amount —
## emits nothing, so a repairer parked on a healthy target doesn't repaint the HP bar
## every physics frame.
##
## REFUSED WHILE THE HOST IS STAGGERED: a piece that has just been hit cannot be mended
## through the fire it is taking, so healing joins the channeled actions stagger already
## suppresses (Build, Repair, PLANT). Enforced HERE rather than at each mender so the
## Repair command, a heal aura and whatever is added next cannot come to disagree — and a
## staggered patient reads as "not full yet", which keeps a repairer standing by rather
## than dropping its order. See Commandable.is_staggered.
##
## Construction is untouched: advance_build_progress writes hp directly, because raising a
## building is not healing it.
func restore(a_amount: float) -> bool:
	if a_amount <= 0.0:
		return hp >= hp_max
	var host := get_parent() as Commandable
	var is_staggered: bool = host != null and host.is_staggered()
	# A heal that lands takes off whatever an enemy has stuck on the piece — a beacon, a planted
	# charge — whether or not there was any hp to restore, so a heal proc on a whole piece still
	# clears markers its owner may not be able to see.
	if host != null and not is_staggered:
		host.shed_hostile_markers()
	if hp >= hp_max:
		# Whole, but still wearing a marker the stagger kept on: not done yet.
		return not (is_staggered and host.has_hostile_markers())
	if is_staggered:
		return false
	hp = minf(hp + a_amount, hp_max)
	hp_changed.emit(hp, hp_max)
	return hp >= hp_max


## Drop hp straight to 0 without running the damage pipeline, for effects that must
## destroy an entity outright (e.g. SuicideStatusEffect). Death still routes through
## the normal hp <= 0 detection in Commandable._update_state.
func kill() -> void:
	if hp == 0:
		return
	hp = 0
	hp_changed.emit(hp, hp_max)
#endregion
