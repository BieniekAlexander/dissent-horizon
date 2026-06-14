class_name Deposit
extends Entity

## A resource deposit: a neutral, terrain-grid-occupying world structure that a
## player can build a Mine "on top of". The deposit stays the sole grid occupant
## (impassable / navmesh-excluding); the Mine overlays it without registering in
## the grid and the two hold mutual references (see Mine).
##
## `mine` is the covering Mine, or null when the deposit is open for mining. It's
## the single source of truth for "is this deposit already mined" — Mine.valid_placement
## checks it to forbid stacking a second mine, and Mine._on_death clears it so the
## deposit becomes minable again (the deposit itself is never removed from the grid).

#region Properties
var _mine: Commandable = null
var mine: Commandable:
	get: return _mine
	set(value):
		_mine = value
		# Hide the deposit's sprite while a mine covers it (the mine's sprite shows
		# on top); reveal it again when released (e.g. the mine is destroyed).
		var sprite := get_node_or_null("Sprite")
		if sprite != null:
			sprite.visible = value == null
#endregion
