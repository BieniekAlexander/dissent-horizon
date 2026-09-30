class_name Repurposing
extends RefCounted

## Making one piece into another that is built FROM it: the Anarchical an_infrastructure is a
## neutral building (any `variants:` entry of its doc) that the player either built from scratch
## in that building's form, or converted where it stood. The two must end up the SAME piece, so
## both go through here.
##
## The rule: the node keeps the underlying piece's BODY — footprint, HP, and (through its own
## template, see PieceFamilies) price, build time and infrastructure — and takes everything else
## from the target piece's own scene: its id, armour and frame, garrison masks and range bonus,
## vision. "Everything else" is read off the target's PackedScene, not listed here: each property
## the target's doc authored on a gameplay component is copied, so retuning the target's doc (or
## giving it a new authored property on these components) needs no edit to this file.
##
## Deliberately does not touch the commander, the grid or the tree. A fresh instance has none of
## them yet, and a live one has its registry entries and infrastructure credit re-keyed by its
## caller (Build's conversion), which knows the order those have to happen in.

## The nodes of the target scene whose authored properties travel. The root is ".". Everything
## else in the scene is either the underlying piece's body (Structure's footprint, the selection
## shape, the model, the HP bar) or presentation that follows it.
const COMPONENTS: Array[String] = [".", "Defense", "Garrison", "VisionRange"]

## Properties that stay the underlying piece's even on a copied component: HP is the building's
## own, and infrastructure is set from its template below rather than from the target's scene.
const KEPT: Array[StringName] = [&"hp_max", &"infrastructure", &"script"]


## Turn `a_node` — an instance of a scene of some piece with a template (PieceFamilies) — into
## `a_target_id`, in place. See the class doc for what is taken from where. Records the piece it
## was in `built_from` (which prices and times it) and leaves its family's group.
static func into(a_node: Commandable, a_target_id: StringName) -> void:
	var target_tool: Tool = Tool.for_id(a_target_id)
	if a_node == null or target_tool == null or target_tool.packed_scene == null:
		push_error("Repurposing: cannot make %s into %s" % [a_node, a_target_id])
		return
	var original: PieceFamilies.Template = PieceFamilies.template(a_node.id)
	_copy_authored(a_node, target_tool.packed_scene.get_state())
	if original == null:
		return
	a_node.built_from = original.id
	a_node.infrastructure = original.infrastructure
	if a_node.is_in_group(original.family):
		a_node.remove_from_group(original.family)
	# A live garrison host fires with a new bonus from the next tick; its aggro reach follows.
	if a_node.is_inside_tree() and a_node.garrison != null:
		a_node.refresh_aggro_shapes()


static func _copy_authored(a_node: Commandable, a_state: SceneState) -> void:
	for i: int in a_state.get_node_count():
		var path: String = str(a_state.get_node_path(i)).trim_prefix("./")
		if not COMPONENTS.has(path):
			continue
		var component: Node = a_node if path == "." else a_node.get_node_or_null(path)
		if component == null:
			continue
		for j: int in a_state.get_node_property_count(i):
			var property: StringName = a_state.get_node_property_name(i, j)
			if KEPT.has(property) or str(property).begins_with("metadata/"):
				continue
			# The root's Node-level properties (collision layers, transform) are the engine's and
			# the world's to set; only the piece's own script variables — its id — are the piece's.
			if path == "." and not _is_script_variable(component, property):
				continue
			component.set(property, a_state.get_node_property_value(i, j))


static func _is_script_variable(a_node: Node, a_property: StringName) -> bool:
	for info: Dictionary in a_node.get_property_list():
		if info["name"] == a_property:
			return (int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0
	return false
