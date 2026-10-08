class_name SquadPolicy
extends RefCounted

## What a Squad is kept doing. A policy issues its order to the members it is handed — all
## of them when it is new, the idle ones after — and says whether another policy is the same
## standing order, which is what stops a squad being re-ordered every think to where it
## already is. The vocabulary (gdd/systems/ai/squads-and-relations.md §Squads):
##   • StagePolicy   — gather at a point and wait; the reserve.
##   • HoldPolicy    — stand at a post; the army at home.
##   • AssaultPolicy — attack-move on an objective and raze what stands there; the wave.
##   • TacticRulePolicy — a mission's authored rule (scripts/scenario/).
## A subclass overrides both methods; the base issues nothing.


## Give `a_members` this policy's order. The members are live and eligible; a policy that
## leaves some standing (they have arrived) decides that itself.
func issue(_a_members: Array) -> void:
	pass


## Whether `a_other` is the same standing order — the same post within tolerance, the same
## objective. A squad whose policy is replaced by one that is the same keeps its members'
## orders and re-issues only to the idle. Identity by default.
func same_as(a_other: SquadPolicy) -> bool:
	return a_other == self


## A one-word name for the harness and the decision simulations.
func kind() -> StringName:
	return &"none"
