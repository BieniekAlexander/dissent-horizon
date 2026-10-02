@tool
class_name EventGlobalEmp extends AbstractEvent

## Global EMP sanction (Anarchical tier 4): stuns EVERY machine on the map — "EMP all
## units" (gdd/factions/anarchical/anarchical.md).
##
## MAP-WIDE AND BOTH SIDES, deliberately, and the asymmetry IS the mechanic. A stun only
## takes hold on a MECH frame (see StunStatusEffect.affects_frames), and the Anarchists
## are the infantry faction — Irregulars, Sappers, Sharpshooters, Warlords all shrug it
## off — so the side that fires it pays almost nothing while a vehicle-heavy opponent
## stops dead. Sparing the caster's own machines would hand them that for free and erase
## the one real cost of owning a mechanised force as this faction.
##
## It is the only sanction in either sanction grid that ignores its aim point entirely: the
## click is where the player happened to be pointing, and the effect is everywhere. That
## also means it is the one sanction whose `needs_vision` gate is meaningless, so the
## Sanction authors it off.
##
## UNITS ONLY, not structures. The doc says units, and widening it would silence
## defensive turrets and production lines at once — a considerably bigger superweapon
## than a tier-4 cell should be, and one no counterplay exists for.

## The one authored definition of what an EMP IS — frame mask, dead-machine shade and the
## blinking bolt over the host (see StatusEffect's visual declaration). Instanced rather
## than newed up here so this sanction and the Condor's bomb, which drops the same scene,
## cannot end up looking or behaving like two different effects.
const EMP_EFFECT: PackedScene = preload("res://scenes/entities/status_effects/emp.tscn")

## How long the stun lasts, in physics ticks (30/second). Overrides the scene's own
## duration: a superweapon holds a battlefield far longer than one shock-trooper arc.
@export var duration_ticks: int = 150


func execute(a_manager: ScenarioTriggerManager) -> void:
	for node: Node in a_manager.get_tree().get_nodes_in_group("unit"):
		var unit := node as Commandable
		if unit == null or unit.is_queued_for_deletion():
			continue
		# MECH only, and that comes from the scene: an EMP that also stopped infantry would
		# be a plain global freeze, and the faction's whole identity here is that its army
		# ignores it.
		var effect := EMP_EFFECT.instantiate() as StunStatusEffect
		effect.duration_ticks = duration_ticks
		# apply_to removes the effect itself on a BIO host, so every unit can be offered one.
		effect.apply_to(unit)
