class_name Ownership
extends Node

## Ownership component — owns the "which commander does this entity belong to"
## relationship.
##
## Step 3 of the components refactor. Lives in scene composition. Entity
## continues to expose `commander` and `commander_id` as delegating shims so
## existing call sites (build.gd, capture.gd, commander.gd, command_receiver.gd,
## weapon.gd, etc.) don't all have to change at once. New code, and the parts
## of the controller that we're actively decoupling, should go through
## `entity.ownership.commander_id` directly.
##
## Ownership knows nothing about sprites, teams, or visual tinting — that's
## presentation policy and lives elsewhere. It only knows about Commander
## references and emits a signal when they change.

signal commander_changed(old_commander: Commander, new_commander: Commander)

var _commander: Commander
var commander: Commander:
	get: return _commander
	set(value):
		if value == _commander: return
		var old: Commander = _commander
		_commander = value
		commander_changed.emit(old, value)

var commander_id: int:
	get: return _commander.id
