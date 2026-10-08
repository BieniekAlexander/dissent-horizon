class_name Repairs
extends Node

## Declares that this unit can REPAIR — restore hp to damaged friendly MECH-framed
## entities, units and structures alike. Add as a child of any Actor that should
## have the ability; the doc key that creates it is a bare `repairs: true`.
##
## PRESENCE IS THE WHOLE CAPABILITY CHECK today: Repair asks `has_node("Repairs")` and
## nothing else, which is why the spec key is a bool rather than a list. It is a node
## rather than a flag on Actor so the capability has somewhere to grow — a target
## filter (which frames/armours this unit can work on), a per-repair resource cost, or a
## rate that varies by target — without re-plumbing every caller. Contrast Builds, whose
## capability was never presence alone: WHICH structures a unit may place is data, so it
## carries a list from the day it existed.

## HP restored per second, per repairing unit. Repairers do not diminish each other the
## way builders do (see Actor.effective_build_increment): each one applies its own
## rate every tick, so two Kobolds mend twice as fast. That is deliberate — construction
## is one job several units crowd around, while repair is several units each doing their
## own job on the same patient.
##
## NOT doc-governed yet: `repairs:` is a bare bool, so this is scene-authored and the
## default below is what every repairer gets. Give the key a mapping form
## (`repairs: {rate: 12}`) when the first unit needs to differ.
@export var repair_rate: float = 10.0


## HP this unit restores in `a_delta` seconds.
func repair_amount(a_delta: float) -> float:
	return repair_rate * a_delta
