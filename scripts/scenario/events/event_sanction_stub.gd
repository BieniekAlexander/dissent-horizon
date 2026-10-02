@tool
class_name EventSanctionStub
extends AbstractEvent

## A deliberately EMPTY sanction payload: it fires, says so, and does nothing else.
##
## It exists so a faction's sanction grid can be authored in full before the events
## that fill it are written. An SanctionUnlock whose Sanction points here is a real,
## unlockable, deployable cell — it costs dominion, opens the tier below it, supersedes
## its parent and runs its cooldown — so the whole sanction grid (the unlock menu, the tier
## gates, the supersession, the deployable bar) can be played and tested with only a
## couple of the payloads actually built. Replace the Sanction's `event_scene` with the
## real event when it lands; nothing else about the cell changes.
##
## The alternative — leaving `Sanction.event_scene` null — is worse than it looks:
## Sanction.activate refuses outright, so the button arms and then never disarms, which
## reads as a bug rather than as unfinished work.
##
## `sanction_name` is set by Sanction.activate, the same way `commander_id` is.

## Which sanction fired this, for the log line. Blank when something other than an
## Sanction ran it.
@export var sanction_name: String = ""

## Whose sanction it was. Unused beyond the log line — a stub owns nothing.
@export var commander_id: int = 0


func execute(_a_manager: ScenarioTriggerManager) -> void:
	print(
		(
			"[sanction stub] '%s' fired at %s for commander %d — no payload built yet."
			% [
				sanction_name if not sanction_name.is_empty() else name,
				global_position,
				commander_id
			]
		)
	)
