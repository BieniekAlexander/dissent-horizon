@tool
class_name EventRadarScan extends AbstractEvent

## The Colonial Scan family (gdd/factions/colonial/colonial.md): spawns an invisible,
## commander-owned Scout at the clicked position whose VisionRange clears the fog around
## it, then removes itself when its lifespan runs out.
##
## All three tiers are THIS ONE EVENT with different exports, because the tiers differ
## only in how long the eye lasts and what it can see:
##   Scan 1 — radius 10, 15 seconds, no stealth detection
##   Scan 2 — the same reveal, plus it exposes stealthed units
##   Scan 3 — the same again but PERMANENT (`lifespan_seconds` < 0, so the drone gets no
##            Lifespan at all), which is exactly the doc's "hovering unit that floats
##            above the designated position indefinitely ... uncommandable": a Scout is
##            already uncommandable and unselectable, so nothing had to be built for it.
##
## Stealth detection is a DetectionRange child created here rather than authored on
## scout.tscn, so Scan 1's scout genuinely has none — Scout only runs its detection tick
## when the node exists, so the tier difference is real rather than a disabled flag.

const _SCOUT_SCENE: PackedScene = preload("res://scenes/entities/nt_aircraftLight_recon.tscn")

## How far the scan clears fog, in world units.
@export var vision_radius: float = 10.0

## Seconds the scan persists. Negative = permanent (Scan 3).
@export var lifespan_seconds: float = 15.0

## Radius within which the scan also reveals STEALTHED enemies. 0 or less = it does not
## (Scan 1). Separate from `vision_radius` because seeing ground and seeing through
## stealth are different ranges in principle; the shipped tiers set them equal.
@export var detection_radius: float = 0.0

## Commander the revealed vision belongs to. Set by the activating Sanction before
## execute, so the same event serves the human player and any bot.
var commander_id: int = 1

func execute(a_manager: ScenarioTriggerManager) -> void:
	var commander: Commander = a_manager.get_commander(commander_id)
	var map: Map = a_manager.map
	if commander == null or map == null:
		return

	var scout := _SCOUT_SCENE.instantiate() as Commandable
	if scout == null:
		return
	Lifespan.attach(scout, lifespan_seconds)
	_resize_vision(scout)
	_add_detection(scout)
	# Spawn directly (initialize → add to commander) rather than via map.add_entity, whose
	# unit-placement path samples the entity's collision radius — the Scout has no
	# collision shape. This mirrors how EventAbilityIrradiate spawns its projectile.
	scout.initialize(map, commander)
	var xz: Vector2 = VU.inXZ(global_position)
	scout.global_position = Vector3(xz.x, map.terrain_height_at(xz), xz.y)


## Set this scan's VisionRange radius.
##
## The shape is DUPLICATED first: a PackedScene's sub-resources are shared across every
## instance of it, so writing the radius in place would resize every other scan's scout —
## and EventRevealRegion's — along with this one.
func _resize_vision(a_scout: Commandable) -> void:
	var vision := a_scout.get_node_or_null("VisionRange") as CollisionShape3D
	if vision == null or vision.shape == null:
		return
	vision.shape = vision.shape.duplicate()
	var cylinder := vision.shape as CylinderShape3D
	if cylinder != null:
		cylinder.radius = vision_radius


## Give the scout a DetectionRange so Scout._detect_stealthed_units has something to
## query. Built here rather than shipped disabled on the scene so that a tier without
## stealth detection has no node at all and skips the query entirely.
func _add_detection(a_scout: Commandable) -> void:
	if detection_radius <= 0.0:
		return
	var shape := CylinderShape3D.new()
	shape.radius = detection_radius
	# Tall enough to catch aerial units too, matching scout.tscn's own VisionRange.
	shape.height = 100.0
	var node := CollisionShape3D.new()
	node.name = "DetectionRange"
	node.shape = shape
	a_scout.add_child(node)
	# No need to assign Entity.detection_range: the node is attached BEFORE
	# initialize() puts the scout in the tree, so the @onready get_node_or_null that
	# seeds that field resolves it. Adding one after _ready would need the hand-wiring
	# EventInformant does for Stealth.
