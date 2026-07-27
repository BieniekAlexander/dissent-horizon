class_name DominionRoute
extends Node

## A commander's dominion MECHANIC — how its faction earns dominion — and the one thing
## anything outside the mechanic (the bot, first) asks about it. It lives on the faction scene,
## one per faction, so a commander's route follows from its faction with no faction checks.
##
## THE BASE CLASS IS ALSO THE SIMPLEST ROUTE: structures that earn on their own, one of which is
## enough (the Colonial Compound, whose own OccupantDominionGenerator pays). A route whose income
## depends on WHERE its sources stand, or that pays for something other than a standing
## structure, subclasses and answers the questions below differently.
##
## The routes and how the bot reads them: gdd/systems/ai/bot-architecture.md §Dominion routes.
##
## TODO: a route sourced by UNITS (the Anarchist Warlord) is not valued by BotProduction — the
## bot trains Warlords as anti-structure units and earns their dominion by accident. A route
## that pays for DESTROYING structures (the planned Marxist one) has no query here yet, and one
## restricted to extraction sites (the planned Technocratic one) needs a placement rule; each
## adds its own question when it is built.

#region Properties
## The STRUCTURES that are this route's sources: what the bot builds to earn dominion. Scene-
## authored rather than a doc key — each faction has one such piece today.
@export var structure_sources: Array[StringName] = []

## What full_site_gain returns for a route whose sources pay the same wherever they stand.
const NOT_SITE_DEPENDENT: float = -1.0

## Null when the faction is instanced outside a commander (a test or preview harness).
@onready var commander: Commander = get_parent().get_parent() as Commander
#endregion

#region Public API
## The route driving `a_commander`, or null when its faction has none. A subtree search; callers
## go through Commander.dominion_route, which keeps the answer.
static func for_commander(a_commander: Commander) -> DominionRoute:
	if a_commander == null or not is_instance_valid(a_commander):
		return null
	# The route lives on the faction scene, so search that when it exists — the commander's own
	# subtree holds every piece it owns.
	var root: Node = a_commander.faction if a_commander.faction != null else a_commander
	for node: Node in root.find_children("*", "", true, false):
		if node is DominionRoute:
			return node as DominionRoute
	return null


## A snapshot for pricing where one more `a_preview` source would go (see
## DominionSiteSurvey), or null when a source earns the same wherever it stands — the base
## route's case, where one Compound is as good as another and the bot wants exactly one.
func site_survey(_a_preview: Entity) -> DominionSiteSurvey:
	return null


## What a new `a_preview` source standing at `a_world_xz` would CLAIM, as cell -> whether that
## cell would earn anything for it. Empty for a route whose sources claim no ground — which is
## every route but a site-dependent one. What the build preview draws to show a site's worth.
func site_claim(_a_preview: Entity, _a_world_xz: Vector2) -> Dictionary:
	return {}


## A claimed tile's standing, for drawing the allocation. PENDING means a piece that is planned
## or still going up will change it: a tile a pending source will claim, or one that pays now
## and a planned building will cover.
enum ClaimState { ACTIVE, PENDING_GAIN, PENDING_LOSS }


## Every tile this route's sources claim, as cell -> ClaimState, pending pieces included —
## what the build preview draws under ANY structure being placed, since covering a claimed tile
## costs income whatever is built on it. Empty for a route that claims no ground.
func claim_layer() -> Dictionary:
	return {}


## A value that changes whenever site_claim's answers could — for a caller that redraws only on
## change. Null for a route that claims no ground.
func claim_key() -> Variant:
	return null


## Dominion/s this route pays on its OWN sweep, beyond any DominionGenerator component (which
## Commander counts itself). 0 for a route that pays only through generators — the base route.
func collection_rate() -> float:
	return 0.0


## How much collection_rate will change once everything ordered is up — pending sources added,
## and ground a planned building will cover taken away, so it may be negative.
func pending_rate_change() -> float:
	return 0.0


## What one `a_preview` source earns per cycle with nothing else claiming around it — the scale
## a survey's gains are read against. NOT_SITE_DEPENDENT for the base route.
func full_site_gain(_a_preview: Entity) -> float:
	return NOT_SITE_DEPENDENT
#endregion
