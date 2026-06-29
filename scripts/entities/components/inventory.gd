class_name Inventory
extends Node

## An entity's single inventory: both the ability ToolSpecs it owns AND the
## items it is physically carrying. The former roster of carried items used to
## live on Entity (the `inventory` array + `inventory_capacity`); those have
## been reconciled into this component so a unit has one inventory, not two.
##
## - Abilities: each ToolSpec grants one Ability.Type and tracks its own
##   charge/reload state, ticked here every physics frame (counterpart to
##   Loadout, which holds Weapon children).
## - Carried items: Entities held by the unit (e.g. Stars a Technician picks
##   up), bounded by item_capacity.

#region Properties

#region Abilities
## Ability.Type values this inventory starts with, authored per-scene (mirrors
## Entity.attributes_list). One ToolSpec is created per entry at _ready with
## default charge/reload values. Exported as ints because Godot serializes enum
## values as ints; each entry should be an Ability.Type member.
@export var initial_abilities: Array[int] = []

var tool_specs: Array[ToolSpec] = []
#endregion

#region Carried items
## Maximum number of items this unit can carry at once.
@export var item_capacity: int = 1
## When true, carried items are returned to their original commanders when the
## holder dies. When false they are freed with the holder.
@export var preserve_occupants: bool = true

## Entities currently being carried (e.g. Stars). Moved here from the former
## Entity.inventory array as part of the inventory reconciliation.
var items: Array[Entity] = []
#endregion

#endregion

#region Lifecycle
func _ready() -> void:
	for ability_type in initial_abilities:
		tool_specs.append(ToolSpec.new(ability_type))

func _physics_process(_delta: float) -> void:
	for spec in tool_specs:
		spec.tick()

## Free any carried units that are detached from the tree (e.g. units imprisoned by
## a stock truck or internment camp) when this inventory is destroyed, so those
## out-of-tree instances don't leak when their holder dies. In-tree items are left
## alone — they belong to the scene and are freed through it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for item: Entity in items:
			if is_instance_valid(item) and not item.is_inside_tree():
				item.free()
#endregion

#region Public API

#region Abilities
## Returns the ToolSpec granting the given Ability.Type, or null if this
## entity has no slot for it.
func tool_spec_for(a_ability_type: Variant) -> ToolSpec:
	for spec in tool_specs:
		if spec.ability_type == a_ability_type:
			return spec
	return null

func has_ability(a_ability_type: Variant) -> bool:
	return tool_spec_for(a_ability_type) != null
#endregion

#region Carried items
func can_hold_more() -> bool:
	return items.size() < item_capacity

func add_item(a_item: Entity) -> void:
	items.push_back(a_item)

## Removes and returns the most recently added item, or null if empty.
func remove_last_item() -> Entity:
	return items.pop_back() if not items.is_empty() else null

func item_count() -> int:
	return items.size()

func has_items() -> bool:
	return not items.is_empty()

## The first carried item (oldest), or null if none.
func first_item() -> Entity:
	return items[0] if not items.is_empty() else null

## Return all carried Commandables to their original commanders as live scene
## entities, positioned at [spawn_pos]. Items with no valid commander are freed.
## Called when the holder is about to die; clears [items] so _notification(PREDELETE)
## finds nothing to clean up.
func eject_to_scene(spawn_pos: Vector3) -> void:
	for item: Entity in items:
		if not is_instance_valid(item):
			continue
		var cmd: Commander = (item as Commandable).commander \
			if item is Commandable else null
		if cmd == null or not is_instance_valid(cmd):
			item.free()
			continue
		cmd.add_child(item)
		item.global_position = spawn_pos
		(item as Commandable).update_commands(null)
	items.clear()

## Free all carried items without returning them.
## Called when preserve_occupants is false and the holder is destroyed.
func free_items() -> void:
	for item: Entity in items:
		if is_instance_valid(item):
			item.free()
	items.clear()
#endregion

#endregion
