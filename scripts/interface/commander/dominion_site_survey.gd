class_name DominionSiteSurvey
extends RefCounted

## A snapshot of what a dominion route's sources already earn, for pricing where one more would
## go. Taken once (DominionRoute.site_survey) and then asked about as many points as the caller
## likes — the bot spreads that asking over several thinks, so the snapshot is what keeps one
## search's answers consistent with each other.

## Dominion per cycle a new source would ADD standing at `a_world_xz`.
func gain_at(_a_world_xz: Vector2) -> float:
	return 0.0
