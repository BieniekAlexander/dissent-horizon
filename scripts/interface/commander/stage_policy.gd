class_name StagePolicy
extends PostPolicy

## Gather at a point and wait to be handed on: the reserve, staged on the threat side of the
## base until it is worth releasing to the wave. The release rule is the decision side's
## (BotMilitary's reinforce_fraction), not the policy's.


func kind() -> StringName:
	return &"stage"
