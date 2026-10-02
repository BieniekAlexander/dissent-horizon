@tool
class_name EventMortarBarrage extends AbstractEvent

## A barrage called in from OFF the map: `shell_count` shells lob in from beyond the
## perimeter nearest the CASTER and land together on the target point.
##
## The simplest shape an off-map ability can take — it produces projectiles and nothing
## else, so there is no piece to command and nothing to clean up afterwards. Where the
## shells come from is the whole of what makes it different from a Bombard, and that lives
## in OffMapArrival rather than here.
##
## All three Mortar tiers are THIS ONE EVENT with a different `shell_count`, because that
## is the only thing that differs between them — a tier is authored data, not a subclass
## (see gdd/systems/macroeconomics/sanctions/payloads.md).

## Shells thrown by one casting. 4 / 8 / 16 across the three tiers.
@export var shell_count: int = 4

## The shell each one throws. Scene-authored rather than doc-governed, for the same reason
## a Weapon's projectile is: it is a scene reference, not a number.
@export var projectile_scene: PackedScene

## How far each shell's launch point strays from the barrage's single origin, in world
## units — a random XZ direction at a distance in [MIN, MIN + RANGE].
##
## The muzzles are scattered; the AIM is not. Every shell is still launched at the same
## target point, so a barrage converges rather than pattern-bombs, and what the spread buys
## is that sixteen shells arrive as sixteen separate arcs instead of one thick line. XZ
## only: an off-map launch ALTITUDE is not something the player can see or reason about.
const LAUNCH_SPREAD_MIN: float = 1.0
const LAUNCH_SPREAD_RANGE: float = 2.0

## Commander the shells belong to (whose enemies they damage). Set by the activating
## Sanction before execute, so the same event serves the player and any bot.
var commander_id: int = 1

## The building that called it down. Its position decides which edge the barrage comes
## over — see OffMapArrival. Null falls back to the target point, which puts the origin
## on the perimeter nearest where the shells are going: still off the map, just no longer
## keyed to the caster's side of the field.
var caster: Commandable = null


func execute(a_manager: ScenarioTriggerManager) -> void:
	var commander: Commander = a_manager.get_commander(commander_id)
	var map: Map = a_manager.map
	if commander == null or map == null or projectile_scene == null:
		return

	var target_xz: Vector2 = VU.in_xz(global_position)
	var target: Vector3 = Vector3(target_xz.x, map.terrain_height_at(target_xz), target_xz.y)
	var anchor_xz: Vector2 = VU.in_xz(caster.global_position) if caster != null else target_xz
	var origin_xz: Vector2 = OffMapArrival.entry_xz(map, anchor_xz)

	for _i: int in maxi(shell_count, 0):
		_launch_shell(map, commander, origin_xz + _launch_offset(), target)


## One shell, from `origin_xz` to `target`.
##
## Added via initialize() rather than Map.add_entity, matching EventAbilityIrradiate: the
## entity placement path spreads units off a MOVEMENT_OBSTRUCTION shape that a projectile
## does not carry.
func _launch_shell(
	a_map: Map, a_commander: Commander, a_origin_xz: Vector2, a_target: Vector3
) -> void:
	var shell: Entity = projectile_scene.instantiate() as Entity
	if shell == null:
		return
	shell.initialize(a_map, a_commander)
	shell.global_position = Vector3(
		a_origin_xz.x, a_map.terrain_height_at(a_origin_xz), a_origin_xz.y
	)
	Emitter.launch(shell, null, a_target)


## A random XZ displacement for one shell's muzzle (see LAUNCH_SPREAD_MIN).
##
## Through `SU.rng` rather than the global generator, for the reason every other gameplay
## draw is: a barrage is part of the simulation, so a run that cannot reproduce where its
## shells came from cannot be replayed. The seeded-randomness audit named only the hitscan
## spread and ScenarioExpression; this was a third site it missed.
static func _launch_offset() -> Vector2:
	var bearing: float = SU.rng.randf() * TAU
	return (
		Vector2(cos(bearing), sin(bearing))
		* (LAUNCH_SPREAD_MIN + LAUNCH_SPREAD_RANGE * SU.rng.randf())
	)
