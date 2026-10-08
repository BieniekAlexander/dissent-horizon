class_name EnergyExtractor
extends Node

## Extracts energy from the map cell under the structure each tick and pays
## it into the owning commander's energy pool. Attach as a child of a Actor
## that sits on an energy-bearing cell.

#region Properties
## Energy paid per cycle: 25 per 5 s is 5/s on an extraction site, low on purpose: a site pays
## back slowly and working lithium ponds is necessary early
## (gdd/systems/macroeconomics/pacing/resource-allotment.md §Second pass).
@export var energy_rate: int = 25
## Seconds between payouts. A const as well as the tick count below, because editor tools read
## it without running this script's static initialiser.
const CYCLE_SECONDS: float = 5.0
static var TICK_RATE: int = roundi(CYCLE_SECONDS * TimeUtils.ticks_per_second())
## Physics ticks since this extractor last paid out. Private: the cycle is the
## component's own business, and nothing outside it has cause to move the counter.
var _ticks_elapsed: int = 0

## The FINITE reservoir this extractor draws from, or null when it works an inexhaustible
## host — an extraction site, which never runs out and so has nothing to debit.
##
## Typed to WaterBody because the lithium pond is the only finite reservoir there is. A
## second one widens this type; it does not get a second field, because "where the energy
## comes from" is one question and answering it twice is how an abstraction turns into a
## pair of siblings (~/.claude/CLAUDE.md §1.3).
var reservoir: WaterBody = null
#endregion


#region Public API
func tick() -> void:
	_ticks_elapsed += 1
	if _ticks_elapsed % TICK_RATE != 0:
		return
	# A reservoir decides its own yield: a pond pays a multiple of the extractor's rate and
	# debits itself, so a drained pond simply stops paying rather than needing to be noticed.
	var paid: int = reservoir.extract(energy_rate) if reservoir != null else energy_rate
	if paid <= 0:
		return
	var commandable := get_parent() as Actor
	commandable.commander.add_energy(paid)


#endregion


#region Checks
## An extractor has TWO kinds of place it may go, and they are checked differently because
## they are different shapes of thing.
##
## ON AN EXTRACTION SITE it must sit SQUARELY: the extractor's footprint and the site's share
## a centre (Map.concentric_structure), not merely overlap. There is therefore exactly one
## valid position per site — the one the extractor ends up at anyway, since it is placed onto
## the site — so the ghost the player aims, the blueprint that goes up, and the finished
## extractor all stand in the same spot. An aim that only clips the site is refused here
## rather than accepted and corrected later, and a site that already has an extractor is
## refused outright.
##
## IN A LITHIUM POND there is no host footprint to be concentric with — the pond covers a
## whole basin — so the ordinary empty-cell placement rule applies instead, with the
## submersion gate (Fixture.allow_submerged) doing the work of saying where. An extractor
## in a pond occupies its own cells like any other structure; only the site case overlays.
##
## Both routes are refused for bare dry ground, for other structures, and for deep water.
##
## `a_allow_pond` false shuts the pond route, leaving only the site. That is the case for an
## overlay piece that draws no ENERGY (the Technocratic Lab): a pond is a finite energy
## reservoir (WaterBody.extract), so a piece with nothing to draw from it has no business
## standing in one. Callers derive it with Extractor.works_ponds rather than passing a literal.
static func valid_placement(
	command_message: CommandMessage,
	dimensions: Vector2i,
	allow_uneven_terrain: bool = false,
	allow_submerged_terrain: bool = false,
	a_allow_pond: bool = true
) -> bool:
	var map: Map = command_message.map
	if map == null:
		return false
	var host: Entity = map.concentric_structure(command_message.xz_position, dimensions)
	var site: ExtractionSite = ExtractionSite.of(host)
	if site != null:
		return site.extractor == null
	if host != null or not a_allow_pond:
		return false
	# Water FIRST: an extractor aimed at dry ground is refused for being nowhere near a
	# reservoir, and asking the generic placement rule about it would only produce the same
	# answer at more cost.
	var body: WaterBody = water_body_under(map, command_message.xz_position, dimensions)
	# ONE EXTRACTOR PER BODY, exactly as the ExtractionSite branch above enforces one per
	# site. A pond is a finite charge, so a second extractor on it splits the same total
	# between two structures rather than adding income.
	if body == null or body.has_extractor():
		return false
	return fits_in_pond(command_message, dimensions, allow_uneven_terrain, allow_submerged_terrain)


## The pond half of `valid_placement` WITHOUT the one-per-body claim: whether the footprint
## lies in one body and the ground there takes a structure. For a caller that judges the claim
## itself, from what it believes rather than from the live body (BotEconomy's pond search).
static func fits_in_pond(
	command_message: CommandMessage,
	dimensions: Vector2i,
	allow_uneven_terrain: bool = false,
	allow_submerged_terrain: bool = false
) -> bool:
	var map: Map = command_message.map
	if map == null or water_body_under(map, command_message.xz_position, dimensions) == null:
		return false
	return Fixture.valid_placement(
		command_message, dimensions, allow_uneven_terrain, allow_submerged_terrain
	)


## Whether a footprint centred on `a_world_center` lands entirely in ONE body of water. One
## body rather than any water, because the extractor draws from the body it stands in and
## straddling two would leave "which reservoir" unanswerable.
static func in_water(a_map: Map, a_world_center: Vector2, a_dimensions: Vector2i) -> bool:
	return water_body_under(a_map, a_world_center, a_dimensions) != null


## The single WaterBody covering every cell of the footprint, or null when the footprint is
## dry or spans more than one body. This is what an extractor's reservoir is bound to.
static func water_body_under(
	a_map: Map, a_world_center: Vector2, a_dimensions: Vector2i
) -> WaterBody:
	var body: WaterBody = null
	for cell: Vector2i in a_map.footprint_cells(a_world_center, a_dimensions):
		var here: WaterBody = a_map.water_body_at(cell)
		if here == null or (body != null and here != body):
			return null
		body = here
	return body
#endregion
