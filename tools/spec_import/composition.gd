extends RefCounted

## What a piece is MADE OF, derived from its doc: the root class and the ordered list of
## components the derivation guarantees (composition-rework §Step 4). A new piece's scene is
## built from this list, and an existing one gains any guaranteed component it lacks.
##
## A component with children or authored defaults is an instance of a scene under
## scenes/components/; a plain script component is declared inline. Doc-governed values are
## not here — the sync passes write those after the component exists.

const SpecSchema := preload("res://tools/spec_import/schema.gd")

## Which set of guaranteed components a piece gets. Decided by what the piece can DO, not by
## what it is called: anything that takes orders or can be damaged carries the Actor set.
enum Tier { COMMANDABLE, FEATURE, BODILESS }

const LIBRARY: String = "res://scenes/components/%s.tscn"
const SCRIPT_ENTITY: String = "res://scripts/entities/entity.gd"
const SCRIPT_COMMANDABLE: String = "res://scripts/entities/actor.gd"
const SCRIPTS: String = "res://scripts/entities/components/%s.gd"
const SCRIPT_OWNERSHIP: String = "res://scripts/entities/components/ownership.gd"

const ALL: Array[int] = [Tier.COMMANDABLE, Tier.FEATURE, Tier.BODILESS]
const PHYSICAL: Array[int] = [Tier.COMMANDABLE, Tier.FEATURE]
const ACTOR: Array[int] = [Tier.COMMANDABLE]

## The guaranteed components, in child order. Locomotion — the nav agent, the movement body,
## the avoidance obstacle, the altitude readout — is the MOBILE piece's alone: a structure has
## no use for it, and its footprint is what it pushes against the world with. Keys:
##   name   — the node name, which is also how the runtime finds it
##   scene  — a component-library scene, OR
##   type / script — an inline node
##   props  — raw .tscn values written on creation (inline nodes only)
##   tiers  — the Tier values that get it
##   when   — "mobile", "fixture", "sighted", "visible", "aerial" or "docking" to require that
##            facet as well; absent = always
##   after  — a component an EXISTING scene gains is placed straight after this one, which is
##            where a new scene has it; absent = at the end
##   mobile_props — raw overrides {child path: {property: value}} a MOBILE piece writes on
##                  the instance ("." is the instance root)
## A component's FORMER node names, old → new. A scene still carrying the old name has that
## node renamed in place (SpecSceneSync._rename_legacy_components) rather than gaining a second
## copy beside it, which would leak and crash at teardown (entity-scene-hierarchy.md).
const RENAMED_COMPONENTS: Dictionary = {"Movement": "Locomotion"}

const COMPONENTS: Array[Dictionary] = [
	{"name": "#####STATE#####", "type": "Node", "tiers": PHYSICAL},
	{"name": "NavigationAgent", "scene": "navigation_agent", "tiers": ACTOR, "when": "mobile"},
	{"name": "MovementBody", "scene": "movement_body", "tiers": ACTOR, "when": "mobile"},
	{"name": "Hurtbox", "scene": "hurtbox", "tiers": PHYSICAL},
	{"name": "AggroRangeGround", "scene": "aggro_range", "tiers": ACTOR},
	{
		"name": "VisionRange",
		"scene": "vision_range",
		"tiers": [Tier.COMMANDABLE, Tier.BODILESS],
		"when": "sighted"
	},
	{"name": "Ownership", "type": "Node", "script": "ownership", "tiers": ALL},
	{
		"name": "Locomotion",
		"type": "Node",
		"script": "movement",
		"tiers": ACTOR,
		"when": "mobile",
		"props": {"nav_agent_path": 'NodePath("../NavigationAgent")'}
	},
	# Straight after the locomotion it flies, so it ticks next in tree order, as the flight code
	# did when it lived inside Movement.
	{
		"name": "Aerial",
		"type": "Node",
		"script": "aerial",
		"tiers": ACTOR,
		"when": "aerial",
		"after": "Locomotion"
	},
	{
		"name": "Docking",
		"type": "Node",
		"script": "docking",
		"tiers": ACTOR,
		"when": "docking",
		"after": "Aerial"
	},
	{
		"name": "Structure",
		"type": "Node",
		"script": "structure",
		"tiers": PHYSICAL,
		"when": "fixture"
	},
	{"name": "Defense", "type": "Node", "script": "defense", "tiers": ACTOR},
	{"name": "Veterancy", "type": "Node", "script": "veterancy", "tiers": ACTOR},
	{"name": "#####CONTROLS#####", "type": "Node", "tiers": PHYSICAL},
	{"name": "Selectable", "scene": "selectable", "tiers": PHYSICAL},
	{"name": "#####VISUALS#####", "type": "Node", "tiers": PHYSICAL},
	{
		"name": "HPBar",
		"scene": "hp_bar",
		"tiers": ACTOR,
		"mobile_props":
		{".": {"billboard": "2"}, "HPBarFill": {"billboard": "2"}, "HPBarBack": {"billboard": "2"}}
	},
	{"name": "SelectionIndicator", "scene": "selection_indicator", "tiers": PHYSICAL},
	{
		"name": "CommandLineIndicator",
		"type": "Node3D",
		"script": "command_line_indicator",
		"tiers": ACTOR
	},
	{
		"name": "MeshVisual",
		"type": "Node3D",
		"script": "mesh_visual",
		"tiers": PHYSICAL,
		"when": "visible"
	},
	{
		"name": "AltitudeIndicator",
		"type": "Node3D",
		"script": "altitude_indicator",
		"tiers": ACTOR,
		"when": "mobile"
	},
	{"name": "StatusVisuals", "type": "Node3D", "script": "status_visuals", "tiers": ACTOR},
	{"name": "#####DEBUG#####", "type": "Node", "tiers": PHYSICAL},
	{
		"name": "DebugLabel",
		"scene": "debug_label",
		"tiers": PHYSICAL,
		"mobile_props": {".": {"billboard": "2"}}
	},
	{"name": "AvoidanceObstacle", "scene": "avoidance_obstacle", "tiers": ACTOR, "when": "mobile"},
	{"name": "#####TRIGGERS#####", "type": "Node", "tiers": ACTOR},
	{"name": "TargetIndicator", "scene": "target_indicator", "tiers": ACTOR},
	{"name": "AggroRangeAir", "scene": "aggro_range", "tiers": ACTOR},
	{
		"name": "FootprintVisualizer",
		"scene": "footprint_visualizer",
		"tiers": PHYSICAL,
		"when": "fixture"
	},
]

## What every emission is guaranteed besides its root, its Ownership and its phases: the
## locomotion that runs the phase list, and what it does to what it reaches.
const EMISSION_COMPONENTS: Array[Dictionary] = [
	{"name": "Locomotion", "type": "Node", "script": "phased_locomotion"},
	{"name": "Payload", "type": "Node", "script": "payload"},
]


## A piece that takes orders or can be damaged is a Actor; a fixture that does neither
## is a feature on a plain Entity; anything else has no body at all. "Can be damaged" is asked
## of the doc's shape AND of the flattened spec (`defense.hp` becomes `hp`), since the importer
## composes from the latter.
static func tier(spec: Dictionary) -> Tier:
	if SpecSchema.is_commandable(spec) or spec.has("defense") or spec.has("hp"):
		return Tier.COMMANDABLE
	if SpecSchema.is_fixture(spec):
		return Tier.FEATURE
	return Tier.BODILESS


static func is_mobile(spec: Dictionary) -> bool:
	return spec.has("movement")


## Whether the piece sees: unless its doc switched vision off (`false`, or left empty, both
## normalised to 0 by SpecRegistry._check_radius).
static func is_sighted(spec: Dictionary) -> bool:
	return not spec.has("vision") or float(spec["vision"]) > 0.0


static func root_script(spec: Dictionary) -> String:
	return SCRIPT_COMMANDABLE if tier(spec) == Tier.COMMANDABLE else SCRIPT_ENTITY


## Raw root properties. A mobile Actor collides on layer 1 like every unit; anything else
## carries no physics layer of its own — Entity.refresh_movement_collision decides at runtime.
static func root_props(spec: Dictionary) -> Dictionary:
	var mobile_actor: bool = tier(spec) == Tier.COMMANDABLE and is_mobile(spec)
	return {
		"collision_layer": "1" if mobile_actor else "0",
		"collision_mask": "1" if mobile_actor else "0"
	}


## The guaranteed components for `spec`, in child order.
static func components(spec: Dictionary) -> Array[Dictionary]:
	var piece_tier: Tier = tier(spec)
	var out: Array[Dictionary] = []
	for entry: Dictionary in COMPONENTS:
		if not (entry["tiers"] as Array).has(piece_tier):
			continue
		match str(entry.get("when", "")):
			"mobile":
				if not is_mobile(spec):
					continue
			"fixture":
				if not SpecSchema.is_fixture(spec):
					continue
			"sighted":
				if not is_sighted(spec):
					continue
			"visible":
				if SpecSchema.wants_no_visual(spec):
					continue
			"aerial":
				if not spec.has("aerial"):
					continue
			"docking":
				if not bool(spec.get("docking", false)):
					continue
		out.append(entry)
	return out


static func scene_path(entry: Dictionary) -> String:
	return LIBRARY % entry["scene"] if entry.has("scene") else ""


static func script_path(entry: Dictionary) -> String:
	return SCRIPTS % entry["script"] if entry.has("script") else ""
