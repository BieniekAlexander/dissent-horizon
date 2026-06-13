@tool
class_name Mine
extends Commandable

## A Mine is built "on top of" a Deposit. It does NOT occupy the terrain grid
## itself — the Deposit stays the sole grid occupant; the Mine overlays it and the
## two hold mutual references (see Map.add_structure routing and Deposit). The
## Mine's OreExtractor child does the actual ore collection (generic, unchanged).

## The deposit this mine sits on. Set by the build path at runtime (Map.add_structure)
## or authored in a scene (and auto-created by the editor convenience below).
@export var deposit: Deposit


## A mine may only be placed on a Deposit that has no mine yet. The mine binds to
## (and overlays) the whole deposit object, so it's enough that the clicked cell
## belongs to a free deposit — any cell of a multi-cell deposit works. This forbids
## building on bare ground, on other structures, and stacking a second mine on one
## deposit. (a_dimensions is unused: the mine doesn't occupy the grid itself.)
static func valid_placement(
	a_command_message: CommandMessage,
	_a_dimensions: Vector2i,
	_a_allow_uneven_terrain: bool = false
) -> bool:
	var map: Map = a_command_message.map
	if map == null:
		return false
	var cell: Vector2i = map.world_to_grid(a_command_message.xz_position)
	if not map.grid_coordinates_in_bounds(cell):
		return false
	var occupant = map.cell_grid[cell.x][cell.y]
	return occupant is Deposit and (occupant as Deposit).mine == null


## Link this mine to its deposit (both directions).
func bind_deposit(a_deposit: Deposit) -> void:
	deposit = a_deposit
	if a_deposit != null:
		a_deposit.mine = self


func _on_death() -> void:
	# The deposit is never removed from the grid; just release it so it can be
	# mined again. super() handles the rest of the structure teardown.
	if deposit != null and is_instance_valid(deposit):
		deposit.mine = null
	super()


### EDITOR CONVENIENCE
func _ready() -> void:
	if Engine.is_editor_hint():
		# Defer so the node's owner/parent are settled before we add a sibling.
		call_deferred(&"_ensure_editor_deposit")
		return
	super()


## When a Mine is authored into a scene without a deposit, auto-create a linked
## Deposit sibling at the same spot so the mine is valid. Guarded on deposit==null
## so it runs once and never fights the user (deleting the deposit clears the link,
## which correctly recreates one — a mine without a deposit is invalid anyway).
func _ensure_editor_deposit() -> void:
	if not Engine.is_editor_hint() or deposit != null:
		return
	# owner==null means this Mine is itself the scene being edited (opened directly),
	# not an instance placed inside another scene — nothing to attach to.
	var scene_owner := owner
	var parent := get_parent()
	if scene_owner == null or parent == null:
		return
	var d: Deposit = load("res://scenes/structures/deposit.tscn").instantiate()
	parent.add_child(d)
	d.owner = scene_owner
	d.global_transform = global_transform
	d.name = name + "Deposit"
	deposit = d
