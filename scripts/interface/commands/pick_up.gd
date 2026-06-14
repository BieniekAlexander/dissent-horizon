class_name PickUp
extends Command

#region State updates
func should_move(a_actor: Commandable) -> bool:
	return !SU.unit_is_close_to_target(a_actor, message.target)

func can_act(a_actor: Commandable) -> bool:
	var inv := a_actor.ability_inventory
	return inv != null \
		and SU.unit_is_close_to_target(a_actor, message.target) \
		and inv.can_hold_more()

func fulfill_action(a_actor: Commandable) -> Variant:
	# TODO:
	# 1: make sure that the star is getting removed from the map in every which way
	# 2: the anima is not interpreting any commands queued after pickup - why?
	var item: Entity = message.target
	item.get_parent().remove_child(item)
	a_actor.ability_inventory.add_item(item)
	return null
#endregion
