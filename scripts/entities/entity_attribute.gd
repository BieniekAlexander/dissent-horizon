class_name EntityAttribute

enum Type {
	IS_GROUNDED,
	IS_FLYING,
	HAS_STEALTH,
	IS_BIOLOGICAL,
	# extend as needed
}

static var evaluators: Dictionary = {
	Type.IS_GROUNDED: func(e: Node) -> bool:
		var m: Movement = e.get_node_or_null("Movement") as Movement
		return m == null or m.mode == Movement.Mode.GROUNDED_DIRECT,
	Type.IS_FLYING: func(e: Node) -> bool:
		var m: Movement = e.get_node_or_null("Movement") as Movement
		return m != null and (m.mode == Movement.Mode.FLYING or m.mode == Movement.Mode.HOVERING),
	Type.HAS_STEALTH: func(e: Node) -> bool:
		return e.get_node_or_null("Stealth") != null,
	Type.IS_BIOLOGICAL: func(e: Node) -> bool:
		var d: Defense = e.get_node_or_null("Defense") as Defense
		return d != null and d.frame_type == Defense.FrameType.BIOLOGICAL,
}

static func evaluate(attribute: Type, entity: Node) -> bool:
	var fn: Callable = evaluators.get(attribute)
	return fn.call(entity) if fn != null else false
