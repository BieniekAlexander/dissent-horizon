## Handles a serialized representation of an "event",
## which encapsulates a group of entities entering the a_map from "nothing",
## e.g. a random spawning of a star or a player casting a spell
class_name EventUtils

static func render_event_config(a_event_config: Dictionary, a_frame: int) -> Variant:
	## Sets the next timer frame for event activation, and decreases counts
	# TODO find better function name annd wording
	var time_spec = a_event_config["time_specs"][0]
	if !time_spec.has("count"): time_spec["count"] = 1
	
	if time_spec["count"]==0:
		a_event_config["time_specs"].remove_at(0)
		
		if a_event_config["time_specs"].size()==0:
			return null
		else:
			time_spec = a_event_config["time_specs"][0]
	
	a_event_config["timer"] = TimeUtils.get_frame_duration_from_time_spec(time_spec)+a_frame
	time_spec["count"] -= 1
	return a_event_config

static func load_entities_from_event(
	a_event_config: Dictionary,
	a_map: Map,
	commanders: Array,
	rebake_nav_mesh: bool = true
) -> Array[Entity]:
	var new_entitites: Array[Entity] = []
	
	for key in a_event_config["owners"].keys():
		var owner_config = a_event_config["owners"][key]
		var entities_data = owner_config["entities"]
		var commander: Commander = commanders[int(key)]
		var new_guys = []
		
		for data in entities_data:
			var count: int = int(data.get("count", 1))
			var scene = load(data["res"])
			
			for n in range(count):
				var new_guy = scene.instantiate()
				new_entitites.append(new_guy)
				new_guys.append(new_guy)
				a_map.add_entity(
					new_guy,
					Vector2i(data["loc"][0], data["loc"][1]),
					commander
				)
			
			var command = (
				Command.load_command_from_dictionary(owner_config["command"], a_map)
				if owner_config.has("command")
				else null
			)
			
			if command!=null:
				for g in new_guys:
					if g is Commandable:
						g.update_commands(command)
	
	if rebake_nav_mesh:
		a_map.nav_region.bake_navigation_mesh()
	
	return new_entitites
