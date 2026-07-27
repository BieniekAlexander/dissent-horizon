class_name EntityRanges
extends RefCounted

## WHAT REACHES PAST A PIECE, as ground-plane shapes the HUD can draw and words it can put
## in a tooltip: how far it sees, how far it detects, how far it will pick a fight on its
## own, and how far its gun carries.
##
## THE SHAPE IS THE COLLISION SHAPE, not a re-derivation of it. Every one of these ranges is
## already a `CollisionShape3D` the simulation queries against — the fog samples the vision
## shape, aggro tests the aggro shape, `Attack` measures the weapon's — so drawing anything
## else would be drawing a lie that happened to agree most of the time.
## `HighlightShape.from_collision_shape` is the whole conversion, and it is the same one the
## objective painter uses, so a range and an objective region cannot disagree about what a
## cylinder looks like from above.
##
## FOUND BY GROUP, not by node path. Every one of these shapes already carries a
## `debug_shape_*` group — the editor colours them from it (see DebugShapeColors) — so the
## set of "shapes worth drawing" is a fact the scenes already state, and the reveal reads it
## rather than keeping a second list of node names that could fall behind. It is also what
## makes a shape nested two levels down (a weapon's AttackRange under Loadout/Gun) findable
## without this file knowing the shape of a loadout.
##
## COLOURED FROM THE SAME TABLE the editor uses, so a shape a designer authored as "the red
## one" is the red one in game too.
##
## WHAT IS DELIBERATELY NOT HERE: selection shapes, movement/navigation bodies, target
## bodies, footprints, trigger areas. Those describe where the piece IS, and a player
## looking at them learns nothing they cannot see by looking at the unit. Only REACH is
## worth drawing, which is exactly the set of groups named below.
##
## Pure and static: given an entity it reads components and returns shapes. Nothing here
## touches the HUD, which is what lets it be tested without one.

#region Kinds
## The reaches worth showing. Each is a separate hoverable fact on the info card, so they
## are named rather than being an untyped list of shapes.
enum Kind {
	VISION,     ## what this piece reveals of the fog
	DETECTION,  ## how close a stealthed enemy has to come to be seen
	AGGRO,      ## how far it will start a fight on its own
	ATTACK,     ## how far its FIRST weapon carries against GROUND targets
	ATTACK_AIR, ## how far its first air-capable weapon carries against AIR targets
	LIBERATION, ## how close a Terrestrial has to be to be converted
	DOMINION,   ## the Warlord's aura, over which colocated infantry bank dominion
	EFFECT,     ## how far an active status effect on it reaches (see StatusEffect.effect_radius)
}

## The kinds measured from the piece's footprint rather than its centre (SU.entities_within,
## SU.is_in_attack_range). VISION is not: fog is stamped from the centre. EFFECT is not:
## an effect's reach is a number on the effect, measured from the host's position.
const HULL_MEASURED: Array = [Kind.DETECTION, Kind.AGGRO, Kind.ATTACK, Kind.ATTACK_AIR,
	Kind.LIBERATION, Kind.DOMINION]

## The scene group each kind's shape carries. EFFECT is absent deliberately: an effect's
## reach is a NUMBER on the effect rather than a body, so it is the one kind built rather
## than found (see _effect_shape).
##
## ATTACK and ATTACK_AIR share one group: a weapon's ground and air reach shapes are both
## `debug_shape_attack_range`, and which layer a shape serves is read off its Weapon the way
## the Weapon itself reads it (see _attack_node).
const GROUPS: Dictionary = {
	Kind.VISION: &"debug_shape_vision_range",
	Kind.DETECTION: &"debug_shape_detection_range",
	Kind.AGGRO: &"debug_shape_aggro_range",
	Kind.ATTACK: &"debug_shape_attack_range",
	Kind.ATTACK_AIR: &"debug_shape_attack_range",
	Kind.LIBERATION: &"debug_shape_liberation_range",
	Kind.DOMINION: &"debug_shape_warlord_dominion",
}

## Reader-facing names, for tooltips and for anything that lists the set.
const TITLES: Dictionary = {
	Kind.VISION: "vision",
	Kind.DETECTION: "detection",
	Kind.AGGRO: "aggro",
	Kind.ATTACK: "attack",
	Kind.ATTACK_AIR: "anti-air attack",
	Kind.LIBERATION: "liberation",
	Kind.DOMINION: "dominion",
	Kind.EFFECT: "effect",
}

## The colour a kind is drawn in — READ FROM THE EDITOR'S OWN TABLE, brightened, because the
## debug colours are authored as translucent fills and these are drawn as outlines.
##
## Not a second palette. A designer who knows the amber circle is aggro must find the amber
## circle is aggro in game, and two tables would be two chances to disagree about that.
static func color_of(a_kind: Kind) -> Color:
	if a_kind == Kind.EFFECT:
		return EFFECT_COLOR
	if a_kind == Kind.ATTACK_AIR:
		return ATTACK_AIR_COLOR
	var color: Variant = DebugShapeColors.GROUP_COLOR.get(String(GROUPS.get(a_kind, &"")))
	return (color as Color) if color is Color else Color.WHITE

## EFFECT has no debug shape and so no entry in that table — it is the one colour named here.
const EFFECT_COLOR: Color = Color(0.56, 0.94, 0.72)
## ATTACK_AIR shares the attack group with ground reach (the editor draws both red), so it is
## the second colour named here: sky blue, for the reach against aircraft.
const ATTACK_AIR_COLOR: Color = Color(0.35, 0.72, 1.0)

## The kinds each info widget reveals when the player hovers it.
##
## Grouped by the QUESTION the widget answers rather than one kind per card: "how far can
## this thing see" is one question with two answers (ordinary sight and stealth detection),
## and "what happens if something walks up to it" is another (how far it shoots, and how far
## out it decides to). Splitting those into four cards would be four hovers to learn one
## thing.
const WEAPON_KINDS: Array = [Kind.ATTACK, Kind.ATTACK_AIR, Kind.AGGRO]
const VISION_KINDS: Array = [Kind.VISION, Kind.DETECTION]
const EFFECT_KINDS: Array = [Kind.EFFECT]
## Everything a piece projects, for a caller that wants the lot rather than one card's worth.
const ALL_KINDS: Array = [
	Kind.VISION, Kind.DETECTION, Kind.AGGRO, Kind.ATTACK, Kind.ATTACK_AIR,
	Kind.LIBERATION, Kind.DOMINION, Kind.EFFECT,
]
#endregion

#region Queries
## Every StatusEffect currently acting on `a_entity`. Effects are children of the entity
## they act on (see StatusEffect.apply_to), so this is a scan of its own children — the same
## shape StatusVisuals and Commandable.is_stunned() use.
static func active_effects(a_entity: Entity) -> Array[StatusEffect]:
	var out: Array[StatusEffect] = []
	if a_entity == null or not is_instance_valid(a_entity):
		return out
	for child: Node in a_entity.get_children():
		if child is StatusEffect and (child as StatusEffect).is_active():
			out.append(child as StatusEffect)
	return out


## The ground-plane footprint of `a_kind` on `a_entity`, or null when the piece has no such
## reach — a structure has no gun, a plain soldier no detection sweep. Null rather than a
## zero-radius circle, so "has none" and "has a tiny one" stay distinguishable.
##
## A reach measured between footprints (HULL_MEASURED) is drawn widened by the piece's own
## footprint, so the ring is where a target's EDGE comes into reach. Exact for a round body;
## a box body is widened as the circle about it, which never under-states the reach.
static func shape_for(a_entity: Entity, a_kind: Kind) -> HighlightShape:
	var shape: HighlightShape = _reach_shape(a_entity, a_kind)
	if shape == null or shape.kind != HighlightShape.Kind.CIRCLE \
			or not HULL_MEASURED.has(a_kind):
		return shape
	return HighlightShape.circle(shape.center, shape.radius + a_entity.hull().extent())


## The reach itself, centred on its node, before any widening by the piece's footprint.
static func _reach_shape(a_entity: Entity, a_kind: Kind) -> HighlightShape:
	if a_kind == Kind.EFFECT:
		return _effect_shape(a_entity)
	var node: CollisionShape3D = _shape_node(a_entity, a_kind)
	return HighlightShape.from_collision_shape(node) if node != null else null


## Every kind in `a_kinds` that `a_entity` actually has, paired with its footprint, as
## `[[Kind, HighlightShape], …]` in the order asked for. Kinds the piece lacks are dropped.
static func shapes_for(a_entity: Entity, a_kinds: Array) -> Array:
	var out: Array = []
	for kind: Variant in a_kinds:
		var shape: HighlightShape = shape_for(a_entity, int(kind))
		if shape != null:
			out.append([int(kind), shape])
	return out


## The XZ radius of `a_kind` on `a_entity`, or -1.0 when it has none.
##
## A single number for a shape that may be a rectangle, because this is what goes in a
## TOOLTIP: a reader wants "reaches 12" and the rings on the ground are where the exact
## footprint is read. A rect reports its larger half-extent, which never under-states it.
static func radius_of(a_entity: Entity, a_kind: Kind) -> float:
	var shape: HighlightShape = _reach_shape(a_entity, a_kind)
	if shape == null:
		return -1.0
	return shape.radius if shape.kind == HighlightShape.Kind.CIRCLE \
		else maxf(shape.half_extents.x, shape.half_extents.y)


## Whether `a_entity` has anything at all to show for `a_kinds`.
static func has_any(a_entity: Entity, a_kinds: Array) -> bool:
	return not shapes_for(a_entity, a_kinds).is_empty()


## The FIRST shape under `a_entity` in `a_group`, in tree order, or null.
##
## FIRST, not widest, and not one shape per weapon: a piece with several guns is rare, the
## first is the one its stat line is written about, and a ring per gun would make the common
## single-weapon case pay for the rare one.
##
## Scoped to this entity's own subtree — `get_tree().get_nodes_in_group` would return every
## such shape in the scene, which is every unit on the map.
static func shape_node_in_group(a_entity: Entity, a_group: StringName) -> CollisionShape3D:
	if a_entity == null or not is_instance_valid(a_entity):
		return null
	for node: Node in a_entity.find_children("*", "CollisionShape3D", true, false):
		if node.is_in_group(a_group):
			return node as CollisionShape3D
	return null


## EVERY shape under `a_entity` in `a_group`, in tree order — for a caller that wants each of
## a piece's weapons rather than its first. Works on an out-of-tree instance too.
static func shape_nodes_in_group(a_entity: Entity, a_group: StringName) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	if a_entity == null or not is_instance_valid(a_entity):
		return out
	for node: Node in a_entity.find_children("*", "CollisionShape3D", true, false):
		if node.is_in_group(a_group):
			out.append(node as CollisionShape3D)
	return out


## The blast radius of what an ability THROWS, read off the emission scene's own HitShape —
## the sphere the damage is actually applied through, so a drawn area of effect and the one
## that lands cannot disagree. 0.0 for an ability that throws nothing, or an emission with no
## blast (a bullet).
##
## Memoized because the aiming preview asks every frame while an ability is armed, and the
## answer is a fact about the SCENE: instantiating it per frame to measure it would allocate
## a projectile sixty times a second to look at one number.
static func emission_radius(a_scene: PackedScene) -> float:
	if a_scene == null:
		return 0.0
	if _emission_radii.has(a_scene):
		return float(_emission_radii[a_scene])
	var radius: float = 0.0
	var probe: Node = a_scene.instantiate()
	var hit := probe.get_node_or_null("HitShape") as CollisionShape3D
	var root := probe as Node3D
	if hit != null and RangeShapes.radius_of(hit.shape) >= 0.0 and root != null:
		# Out of tree, so local transforms: the blast scales with the emission root and with
		# the shape node's own X axis. Same reading Bot._projectile_blast_radius takes.
		radius = RangeShapes.radius_of(hit.shape) * root.scale.x \
			* hit.transform.basis.x.length()
	probe.free()
	_emission_radii[a_scene] = radius
	return radius

static var _emission_radii: Dictionary = {}


## The first weapon itself, or null — what the weapon info widget reads its stats off.
static func first_weapon(a_entity: Entity) -> Weapon:
	if a_entity == null or a_entity.weapon_inventory == null:
		return null
	for child: Node in a_entity.weapon_inventory.get_children():
		var weapon := child as Weapon
		if weapon != null:
			return weapon
	return null
#endregion

#region Private helpers
## EFFECT is the one kind with no collision shape behind it: an effect's reach is a NUMBER
## on the effect, not a body the simulation queries, so it is built as a circle at the host
## rather than converted from a shape. Everything else resolves to a live CollisionShape3D.
static func _effect_shape(a_entity: Entity) -> HighlightShape:
	var widest: float = 0.0
	for effect: StatusEffect in active_effects(a_entity):
		widest = maxf(widest, effect.effect_radius)
	return HighlightShape.circle(a_entity.xz_position, widest) if widest > 0.0 else null


static func _shape_node(a_entity: Entity, a_kind: Kind) -> CollisionShape3D:
	if a_entity == null or not is_instance_valid(a_entity):
		return null
	if a_kind == Kind.AGGRO:
		return _widest_aggro_shape(a_entity)
	if a_kind == Kind.ATTACK or a_kind == Kind.ATTACK_AIR:
		return _attack_node(a_entity, a_kind == Kind.ATTACK_AIR)
	var group: Variant = GROUPS.get(a_kind)
	return shape_node_in_group(a_entity, group) if group is StringName else null


## The first attack-range shape under `a_entity` that serves the AIR layer (`a_air`) or the
## GROUND layer. Read by the same rule Weapon's own `attack_range_shape_ground/_air` use —
## an `AttackRangeAir` / `AttackRangeGround` node serves its one layer, and a lone
## `AttackRange` serves every layer its weapon's target_mask names — so it answers for an
## out-of-tree instance too, where those @onready fields are not yet set. A lone shape that
## serves both layers is returned for both, which is how the reveal learns the two reaches
## are the same ring.
static func _attack_node(a_entity: Entity, a_air: bool) -> CollisionShape3D:
	var layer: int = CollisionLayers.Mask.TARGETABLE_AIR if a_air \
		else CollisionLayers.Mask.TARGETABLE_GROUND
	for node: CollisionShape3D in shape_nodes_in_group(a_entity, GROUPS[Kind.ATTACK]):
		var weapon := node.get_parent() as Weapon
		if weapon == null or node.shape == null:
			continue
		match String(node.name):
			"AttackRangeAir":
				if a_air:
					return node
			"AttackRangeGround":
				if not a_air:
					return node
			_:
				if weapon.target_mask & layer:
					return node
	return null


## Aggro is two volumes, one per target layer, and either may be empty — so the ring drawn
## is the wider one that exists, not whichever node comes first in the tree.
static func _widest_aggro_shape(a_entity: Entity) -> CollisionShape3D:
	var best: CollisionShape3D = null
	for node: CollisionShape3D in a_entity.aggro_shapes():
		if best == null or RangeShapes.xz_radius(node) > RangeShapes.xz_radius(best):
			best = node
	return best
#endregion
