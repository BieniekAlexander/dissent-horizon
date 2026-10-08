@tool
class_name EventInformant extends EventTargetUnit

## Informant sanction (Anarchical column 1): grants a clicked friendly unit permanent
## stealth by attaching a Stealth component at runtime.
##
## The three tiers differ ONLY in which units qualify, so they are one script with an
## authored `eligibility` rather than three subclasses:
##   Informant 1 — an Irregular (`an_bioLight_builder`)
##   Informant 2 — any friendly BIO unit
##   Informant 3 — any friendly unit
##
## Stealth is added rather than toggled: the unit scenes ship without the component, so
## this creates one and wires `Entity.stealth` by hand. That field is seeded by
## get_node_or_null at _ready and stays null for a component added later, so without the
## assignment every reader (the per-tick unstealth countdown, the sprite alpha, enemy
## detection) would miss it and the unit would carry an inert node.

## Which friendly units this tier may stealth.
enum Eligibility {
	BUILDER = 0,  ## Irregulars only
	ANY_BIO = 1,  ## any biological unit
	ANY = 2,  ## anything you own
}

@export var eligibility: Eligibility = Eligibility.BUILDER


func _qualifies(a_candidate: Actor) -> bool:
	# Already stealthed is not a candidate, so a click near a mixed group finds a unit the
	# sanction can actually do something to instead of no-oping on the nearest one.
	if a_candidate.stealth != null:
		return false
	match eligibility:
		Eligibility.BUILDER:
			return a_candidate.id == EntityIds.AN_BIO_LIGHT_BUILDER
		Eligibility.ANY_BIO:
			return (
				a_candidate.defense != null
				and a_candidate.defense.frame_type == Defense.FrameType.BIO
			)
	return true


func execute(a_manager: ScenarioTriggerManager) -> void:
	var target: Actor = _find_target_unit(a_manager)
	if target == null:
		return
	var stealth := Stealth.new()
	stealth.name = "Stealth"
	# add_child runs Stealth._ready, which registers the entity on the STEALTH collision
	# layer; refresh_movement_collision preserves that bit.
	target.add_child(stealth)
	target.stealth = stealth
