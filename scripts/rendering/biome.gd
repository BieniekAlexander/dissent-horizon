@tool
class_name Biome
extends Resource

## A planet's look: every colour the ground, the props, the water and the light take, in one
## place. Pure AESTHETIC parameters — nothing here feeds heights, passability, sites,
## navigation or vision, so the same map plays identically under any biome
## (gdd/setting/natural-environment.md §Map parameters and aesthetic parameters are separate).
##
## A Map names its biome (`Map.biome`); a map that names none is drawn with DEFAULT_PATH. The
## terrain renderers, MapDecorator, WaterBody and the scenario's default lighting each read the
## biome through `Biome.of` and push it into their own materials.

#region Constants
## The biome a map is drawn with when it names none. Not a neutral palette: constraint 7 of the
## setting note rules out an Earth-like look even as a placeholder.
const DEFAULT_PATH: String = "res://resources/biomes/saltglass.tres"

## The colour roles a doodad mesh is painted with (DoodadLibrary bakes the role into each
## vertex; doodad.gdshader looks the colour up here). Order is the shader's array order.
enum PropRole {
	WOOD,
	DEAD_WOOD,
	FOLIAGE,
	SHRUB,
	GRASS,
	REED,
	STONE,
	STONE_DARK,
	BLOOM_A,
	BLOOM_B,
	BLOOM_C,
}
## Size of doodad.gdshader's role_colors array; must equal PropRole's member count.
const PROP_ROLE_COUNT: int = 11
## How many bloom colours a biome carries (BLOOM_A..BLOOM_C).
const BLOOM_COUNT: int = 3
#endregion

#region Ground
@export_group("Ground")
## Ground colour per tile type, keyed by TileType.name. A type the biome does not name falls
## back to `fallback_ground`, never to the catalog's own colour: the catalog's colours are an
## Earth placeholder, and a biome must own the whole ground.
@export var ground_colors: Dictionary[String, Color] = {}
@export var fallback_ground: Color = Color(0.5, 0.5, 0.5)
## Impassable rock, the two ends of its noise and banding.
@export var rock_light: Color = Color(0.5, 0.5, 0.5)
@export var rock_dark: Color = Color(0.25, 0.25, 0.25)
## Pass-7 ground paint (MapDecoration.ground_overlay channels R, G, B, A).
@export var growth_color: Color = Color(0.5, 0.5, 0.5)
@export var trail_color: Color = Color(0.5, 0.5, 0.5)
@export var scree_color: Color = Color(0.5, 0.5, 0.5)
@export var shore_color: Color = Color(0.5, 0.5, 0.5)
## The passability ink line. Kept near-black in every biome: it is the binary "units stop
## here" cue (terrain-readability.md), not decoration.
@export var outline_color: Color = Color(0.1, 0.1, 0.1)
#endregion

#region Water
@export_group("Water")
@export var shallow_water: Color = Color(0.42, 0.72, 0.85)
@export var deep_water: Color = Color(0.10, 0.30, 0.60)
## The hues a charged pond may take — each one a colour real brine takes, from its chemistry
## or from the salt-loving life the star's light allows (natural-environment.md §Lithium ponds
## are cultivated). A pond's pick is derived, never stored: see pond_hue.
@export var pond_hues: Array[Color] = []
## The evaporite crust along a pond's shore and the ground beside it: salt, so pale everywhere.
@export var pond_crust: Color = Color(0.88, 0.86, 0.82)
#endregion

#region Props
@export_group("Props")
@export var wood: Color = Color(0.36, 0.25, 0.16)
@export var dead_wood: Color = Color(0.40, 0.36, 0.31)
@export var foliage: Color = Color(0.25, 0.44, 0.17)
@export var shrub: Color = Color(0.20, 0.36, 0.15)
@export var grass: Color = Color(0.36, 0.52, 0.20)
@export var reed: Color = Color(0.45, 0.50, 0.24)
@export var stone: Color = Color(0.47, 0.45, 0.42)
@export var stone_dark: Color = Color(0.37, 0.35, 0.33)
## BLOOM_COUNT accent colours for flowering props; fewer repeat the last.
@export var blooms: Array[Color] = []
#endregion

#region Light
@export_group("Light")
## The key and fill suns of the default rig (scenes/environment/default_lighting.tscn). The
## star's temperature lives here; the angles stay the rig's.
@export var key_light_color: Color = Color(1, 0.96, 0.88)
@export var key_light_energy: float = 1.1
@export var fill_light_color: Color = Color(0.7, 0.8, 1)
@export var fill_light_energy: float = 0.3
## The hemispheric ambient: the sky's colour from above, the ground's bounce from below.
@export var sky_color: Color = Color(0.56, 0.66, 0.8)
@export var ground_bounce_color: Color = Color(0.3, 0.26, 0.21)
@export var ambient_energy: float = 0.7
#endregion


#region Public API
## The biome `a_node` is drawn with: its Map's, or the default when it has no Map ancestor or
## the Map names none.
static func of(a_node: Node) -> Biome:
	var node: Node = a_node
	while node != null:
		if node is Map:
			return (node as Map).active_biome()
		node = node.get_parent()
	return default_biome()


static func default_biome() -> Biome:
	return load(DEFAULT_PATH) as Biome


## The colour for a tile type named `a_name`.
func ground_color(a_name: String) -> Color:
	return ground_colors.get(a_name, fallback_ground)


## The terrain shader's `tile_colors` array: one entry per catalog index, padded to `a_size`
## with the fallback.
func tile_color_array(a_catalog: TerrainTileCatalog, a_size: int) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(a_size)
	out.fill(fallback_ground)
	if a_catalog == null:
		return out
	for i: int in mini(a_catalog.types.size(), a_size):
		var type: TileType = a_catalog.types[i]
		if type != null:
			out[i] = ground_color(type.name)
	return out


## The charged hue of the pond flooded from `a_seed_cell`. Derived from the seed cell rather
## than stored on the body, so the hue follows the biome and the map file holds no colour —
## and a map still looks the same on every load. A biome with no hues leaves ponds the deep
## water's colour, which reads as uncharged: author at least one.
func pond_hue(a_seed_cell: Vector2i) -> Color:
	if pond_hues.is_empty():
		return deep_water
	return pond_hues[posmod(hash(a_seed_cell), pond_hues.size())]


## doodad.gdshader's `role_colors`, indexed by PropRole.
func prop_role_colors() -> PackedColorArray:
	var out := PackedColorArray([wood, dead_wood, foliage, shrub, grass, reed, stone, stone_dark])
	for i: int in BLOOM_COUNT:
		out.append(_bloom(i))
	return out


## Tint the default rig's suns. Leaves the rig's angles alone, and any light it lacks.
func dress_lighting(a_rig: Node) -> void:
	var key := a_rig.get_node_or_null("KeySun") as DirectionalLight3D
	if key != null:
		key.light_color = key_light_color
		key.light_energy = key_light_energy
	var fill := a_rig.get_node_or_null("FillSun") as DirectionalLight3D
	if fill != null:
		fill.light_color = fill_light_color
		fill.light_energy = fill_light_energy


## A copy of `a_base` (the project's default Environment) with this biome's ambient: its sky
## material's colours and the ambient energy. Null when `a_base` is null.
func environment_from(a_base: Environment) -> Environment:
	if a_base == null:
		return null
	var env := a_base.duplicate(true) as Environment
	env.ambient_light_energy = ambient_energy
	var sky_material := env.sky.sky_material as ProceduralSkyMaterial if env.sky != null else null
	if sky_material != null:
		sky_material.sky_top_color = sky_color
		sky_material.sky_horizon_color = sky_color.lerp(ground_bounce_color, 0.25)
		sky_material.ground_bottom_color = ground_bounce_color
		sky_material.ground_horizon_color = ground_bounce_color.lerp(sky_color, 0.25)
	return env


#endregion


#region Private helpers
func _bloom(a_i: int) -> Color:
	if blooms.is_empty():
		return foliage
	return blooms[mini(a_i, blooms.size() - 1)]
#endregion
