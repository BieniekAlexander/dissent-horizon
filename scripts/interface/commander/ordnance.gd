class_name Ordnance extends Resource

## A commander-level ordnance the player can activate at a chosen map position.
## On activation it instantiates `event_scene` — a scene whose root is an
## AbstractEvent — positions it at the target, executes it, then frees it. A
## cooldown gates re-use.
##
## Ordnances are data, not code: this is the one and only Ordnance class. Each
## instance is authored (name, cooldown, event scene) and wrapped in an
## OrdnanceUnlock on a Faction's ordnance DAG; the specific behaviour lives in the
## referenced event scene rather than in an Ordnance subclass. OrdnanceArsenal
## duplicates it per-commander so cooldowns are independent.

## How the bot aims this ordnance (the human aims it by clicking). The chosen
## engagement zone is the same — defend the base, else strike the enemy — but the
## aim point within it differs by ordnance kind. See BotOrdnance.
enum Targeting {
	## Aim at the densest cluster of enemy units, to maximise an area effect
	## (e.g. Irradiate's radiation field).
	ENEMY_CLUSTER,
	## Aim where freshly-spawned allies should land: at the defended structure when
	## defending, on our side of the front when attacking (e.g. Ambush's irregulars).
	REINFORCE,
}

## Display name, shown on the ordnance bar button.
@export var ordnance_name: String = ""

## Seconds before this ordnance can be used again after activation.
@export var cooldown_duration: float = 60.0

## Scene instantiated and executed when this ordnance activates. Its root node
## must be (or extend) AbstractEvent.
@export var event_scene: PackedScene

## How the bot aims this ordnance.
@export var targeting: Targeting = Targeting.ENEMY_CLUSTER

## World-space radius the ordnance's effect covers. The bot uses it to score
## cluster targets — how many enemies a single drop would catch.
@export var effect_radius: float = 6.0

## Minimum enemy units a drop must catch (within effect_radius) for the bot to
## judge an ENEMY_CLUSTER ordnance worth spending. Keeps it from wasting a charge
## on a lone scout.
@export var min_targets: int = 2

## Runtime cooldown state. Not exported: a freshly duplicated ordnance starts
## ready (0.0), which is exactly what each commander should get.
var _cooldown_remaining: float = 0.0

func is_ready() -> bool:
	return _cooldown_remaining <= 0.0

func cooldown_remaining() -> float:
	return _cooldown_remaining

## 0.0 = cooldown just started, 1.0 = ready.
func cooldown_progress() -> float:
	if cooldown_duration <= 0.0:
		return 1.0
	return 1.0 - (_cooldown_remaining / cooldown_duration)

func tick(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)

## Execute the ordnance at the given world position on behalf of `commander_id` by
## instantiating its event scene. The event acts for that commander (spawns its
## units, damages its enemies). Starts the cooldown on success.
func activate(position: Vector3, manager: ScenarioTriggerManager, commander_id: int) -> void:
	if not is_ready() or event_scene == null:
		return
	var event: AbstractEvent = event_scene.instantiate() as AbstractEvent
	if event == null:
		return
	manager.add_child(event)
	event.global_position = position
	# Events that spawn/own things read commander_id; a no-op on those that don't.
	event.set("commander_id", commander_id)
	event.execute(manager)
	event.queue_free()
	_cooldown_remaining = cooldown_duration
