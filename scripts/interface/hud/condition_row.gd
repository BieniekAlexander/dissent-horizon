class_name ConditionRow
extends HFlowContainer

## WHAT IS TRUE OF THE SELECTED PIECE RIGHT NOW, beyond its numbers: an effect acting on it,
## and what it is producing. One card each, drawn only for a SINGLE selection.
##
## THIS ROW IS FOR THE SPECIFIC, and [InfoWidgetRow] above it is for the ubiquitous. A
## mechanic various units across the game use — hit points, a gun, sight, a garrison — is a
## widget up there in a fixed order the player learns once. Something particular to a faction
## or a piece is a card down here, where the set changes with what is selected. See
## gdd/systems/ux/ui/condition-cards.md §Which row.
##
## THREE SOURCES TODAY, and the row is the place they are brought together:
##
##   * ACTIVE STATUS EFFECTS — nodes on the host, temporary, drawn with a depletion sweep.
##     The world already floats an icon over an affected unit (StatusVisuals); a billboard
##     says *something is on it* and only a card can say WHAT, so the two share their art.
##   * HOLD FIRE — the piece's own Commandable.is_holding_fire, persistent and neutral, drawn
##     with the same badge StatusVisuals floats over it. Its owner's to see only.
##   * PRODUCTION — an extractor's energy, a generator's dominion. Persistent, so no sweep,
##     and badged with what it is banking per cycle. These have no card of their own anywhere
##     else: the economy panel gives a commander-wide rate, which never says WHICH building
##     is earning it.
##
## SINGLE SELECTION ONLY, matching the widget row: "what is happening to it" has no answer for
## a mixed group, and a row that merged twelve units' conditions would say a squad is stunned
## when one member is.
##
## Everything here builds a [ConditionCard], so a status effect and a production card differ
## only in the channels they light — which is the point of having one card class.

#region Constants
## Drawn when a condition names no title — loud rather than blank, the same way
## VerboseTooltipButton treats a missing tooltip.
const UNNAMED_TITLE: String = "?"

## Seconds in one generation cycle, for the copy. Both generators share the period, and it is
## derived from the component rather than typed so a change to it re-words the tooltip.
static var CYCLE_SECONDS: float = float(DominionGenerator.TICK_RATE) \
	/ float(Engine.physics_ticks_per_second)
#endregion

#region Properties
## Raised while the pointer is over a card whose condition reaches past its host, and when it
## leaves. Same payload as the other info rows', so the controller has one thing to listen for.
signal ranges_hovered(entity: Entity, kinds: Array)
signal ranges_unhovered()

## The set of cards currently drawn, so an unchanged set costs no rebuild.
var _drawn: String = ""
## The piece the cards belong to — the host of any range a hover asks for.
var _host: Commandable = null
#endregion

#region Public API
## Redraw for `a_selection`. Anything other than exactly one Commandable empties the row, and
## a piece with nothing to say hides it entirely rather than leaving a gap in the panel.
func update(a_selection: Array) -> void:
	_host = a_selection[0] as Commandable if a_selection.size() == 1 else null
	var effects: Array[StatusEffect] = EntityRanges.active_effects(_host)
	var signature: String = _signature(effects)
	visible = not effects.is_empty() or _produces(_host) or _holds_fire(_host)
	if signature != _drawn:
		_drawn = signature
		_rebuild(effects)
	_refresh(effects)


## The title a status effect is drawn and described under.
static func title_of(a_effect: StatusEffect) -> String:
	return a_effect.title if not a_effect.title.is_empty() else UNNAMED_TITLE


## The stand-in glyph for a condition with no icon: the first letter of its title.
static func letter_for(a_effect: StatusEffect) -> String:
	return title_of(a_effect).substr(0, 1).to_upper()


## Whether `a_piece` banks anything on a cycle — i.e. whether it gets a production card.
static func _produces(a_piece: Commandable) -> bool:
	return a_piece != null and is_instance_valid(a_piece) \
		and (_extractor_of(a_piece) != null or _generator_of(a_piece) != null)


## Whether `a_piece` gets a hold-fire card: it is holding, and it is the player's.
static func _holds_fire(a_piece: Commandable) -> bool:
	return a_piece != null and is_instance_valid(a_piece) and a_piece.is_holding_fire \
		and a_piece.commander_id == RTSController.PLAYER_COMMANDER_ID


static func _extractor_of(a_piece: Commandable) -> EnergyExtractor:
	return a_piece.get_node_or_null("EnergyExtractor") as EnergyExtractor


static func _generator_of(a_piece: Commandable) -> DominionGenerator:
	return a_piece.get_node_or_null("DominionGenerator") as DominionGenerator
#endregion

#region Private helpers
## Identity of the drawn SET: the effect instances, plus which production cards apply.
## Instance ids rather than titles, because two stacks of one effect are two cards.
func _signature(a_effects: Array[StatusEffect]) -> String:
	var parts: Array[String] = []
	for effect: StatusEffect in a_effects:
		parts.append(str(effect.get_instance_id()))
	if _host != null and is_instance_valid(_host):
		if _holds_fire(_host):
			parts.append("hold_fire")
		if _extractor_of(_host) != null:
			parts.append("energy")
		if _generator_of(_host) != null:
			parts.append("dominion")
	return "|".join(parts)


func _rebuild(a_effects: Array[StatusEffect]) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	for effect: StatusEffect in a_effects:
		add_child(_build_effect_card(effect))
	if _host == null or not is_instance_valid(_host):
		return
	if _holds_fire(_host):
		add_child(_build_hold_fire_card())
	if _extractor_of(_host) != null:
		add_child(_build_production_card("Energy", "E",
			"Extracting energy from the ground under it.",
			"An extractor pays its commander every %.0f seconds, for as long as it stands. The "
			% CYCLE_SECONDS
			+ "figure on this card is what THIS building banks per cycle — the economy panel's rate "
			+ "is every extractor you own, and never says which."))
	if _generator_of(_host) != null:
		add_child(_build_production_card("Dominion", "D",
			"Banking dominion every cycle.",
			"The figure is what THIS piece banks per cycle, and it moves: a Compound pays per "
			+ "prisoner, so filling it is what raises the number."))


## The two channels that move while the selection stands still — a duration draining, and a
## production figure changing as what feeds it changes.
func _refresh(a_effects: Array[StatusEffect]) -> void:
	for i: int in a_effects.size():
		var card := get_node_or_null(_effect_card_name(a_effects[i])) as ConditionCard
		if card != null:
			card.refresh(a_effects[i].remaining_fraction(), true)
	if _host == null or not is_instance_valid(_host):
		return
	var extractor: EnergyExtractor = _extractor_of(_host)
	var energy_card := get_node_or_null("Condition_Energy") as ConditionCard
	if extractor != null and energy_card != null:
		energy_card.refresh(1.0, true, "+%d" % extractor.energy_rate)
	var generator: DominionGenerator = _generator_of(_host)
	var dominion_card := get_node_or_null("Condition_Dominion") as ConditionCard
	if generator != null and dominion_card != null:
		dominion_card.refresh(1.0, true, "+%d" % generator.payout())


static func _effect_card_name(a_effect: StatusEffect) -> String:
	return "Condition_%s" % title_of(a_effect).to_pascal_case()


func _build_effect_card(a_effect: StatusEffect) -> ConditionCard:
	var card := ConditionCard.build(
		_effect_card_name(a_effect), letter_for(a_effect), a_effect.indicator_icon,
		a_effect.valence, a_effect.is_temporary()
	)
	var description: String = a_effect.description
	card.simple_tooltip = "%s — %s" % [title_of(a_effect), description] \
		if not description.is_empty() else title_of(a_effect)
	card.verbose_tooltip = a_effect.verbose

	# Only an effect that actually reaches somewhere asks for a reveal; hovering one that acts
	# on its host alone must not leave a stale ring from the card before it.
	var reaches: bool = a_effect.effect_radius > 0.0
	card.mouse_entered.connect(func() -> void:
		if reaches and _host != null:
			ranges_hovered.emit(_host, EntityRanges.EFFECT_KINDS)
		else:
			ranges_unhovered.emit())
	card.mouse_exited.connect(func() -> void: ranges_unhovered.emit())
	return card


## Hold fire: persistent and NEUTRAL — holding is a choice, neither good nor bad for the piece.
func _build_hold_fire_card() -> ConditionCard:
	var card := ConditionCard.build(
		"Condition_HoldFire", "H", StatusVisuals.HOLD_FIRE_ICON, Valence.Kind.NEUTRAL, false
	)
	card.simple_tooltip = "Holding fire — it will not pick targets on its own."
	card.verbose_tooltip = "It shoots only when told to. It will not open fire on what comes " \
		+ "into range, will not shoot back when hit, and will not engage from a Defend or " \
		+ "Patrol. An Attack or Attack-move order lifts the hold."
	card.mouse_entered.connect(func() -> void: ranges_unhovered.emit())
	card.mouse_exited.connect(func() -> void: ranges_unhovered.emit())
	return card


## A production card: persistent (no sweep) and a BOON, since banking is never bad for you.
## It reaches nowhere, so hovering it puts any ring away rather than leaving the last one up.
func _build_production_card(
	a_key: String, a_letter: String, a_description: String, a_verbose: String
) -> ConditionCard:
	var card := ConditionCard.build(
		"Condition_%s" % a_key, a_letter, null, Valence.Kind.BOON, false
	)
	card.simple_tooltip = a_description
	card.verbose_tooltip = a_verbose
	card.mouse_entered.connect(func() -> void: ranges_unhovered.emit())
	card.mouse_exited.connect(func() -> void: ranges_unhovered.emit())
	return card
#endregion
