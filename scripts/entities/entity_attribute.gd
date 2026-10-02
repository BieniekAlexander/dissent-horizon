class_name EntityAttribute

enum Type {
	IS_GROUNDED,
	IS_FLYING,
	HAS_STEALTH,
	IS_BIOLOGICAL,
	# extend as needed
}

static var evaluators: Dictionary = {
	Type.IS_GROUNDED: _is_grounded,
	Type.IS_FLYING: _is_flying,
	Type.HAS_STEALTH: _has_stealth,
	Type.IS_BIOLOGICAL: _is_biological,
}


static func _is_grounded(e: Node) -> bool:
	var m: Movement = e.get_node_or_null("Locomotion") as Movement
	return m == null or not m.is_active or m.mode == Movement.Mode.GROUNDED


static func _is_flying(e: Node) -> bool:
	var m: Movement = e.get_node_or_null("Locomotion") as Movement
	return (
		m != null
		and m.is_active
		and (m.mode == Movement.Mode.FLYING or m.mode == Movement.Mode.HOVERING)
	)


static func _has_stealth(e: Node) -> bool:
	return e.get_node_or_null("Stealth") != null


static func _is_biological(e: Node) -> bool:
	var d: Defense = e.get_node_or_null("Defense") as Defense
	return d != null and d.frame_type == Defense.FrameType.BIO


static func evaluate(attribute: Type, entity: Node) -> bool:
	var fn: Callable = evaluators.get(attribute)
	return fn.call(entity) if fn != null else false
