class_name PassiveAbilityRow
extends HFlowContainer

## The PASSIVE abilities the current selection carries, as a row of cards in the InfoSection.
##
## A passive is never fired: it is attached to whoever owns it and present persistently (see
## AbilityCatalog.is_passive). So it has no command, no charges, no cooldown and no cell on
## any command card — and until this row existed, **nothing on screen said a selected piece
## had one at all.** The player's only evidence of the Anarchists' Scavenge bounty was the
## dominion arriving.
##
## WHY THE INFO PANEL RATHER THAN THE COMMAND GRID. The grid is a set of things you can
## PRESS; a passive cannot be pressed, and a permanently dark button in the grid would read
## as a broken one. The info panel is where a selection describes itself, which is exactly
## what a passive is — a fact about the piece rather than an option.
##
## GREYED MEANS UNPURCHASED, and it means the same thing here as on an ability's command
## button: the piece can carry this, and the commander has not unlocked it (see
## CommandButtonState.Blocker.LOCKED, whose tint this borrows so the two idioms cannot
## drift). A free passive — one no dominion unlocks — is always lit.
##
## TODO: the letter is a stand-in for an icon. Every card draws the first letter of the
## ability's title, which distinguishes the handful a piece can hold but says nothing on its
## own; real art replaces the label and nothing else.

#region Constants
#endregion

#region Properties
## Raised while the pointer is over a passive card whose ability names a reach, and when it
## leaves. Same payload as the other info rows', so the controller has one thing to listen
## for (see gdd/systems/ux/ui/range-reveal.md).
signal ranges_hovered(entity: Entity, kinds: Array)
signal ranges_unhovered

## The set of passives currently drawn, so an unchanged set costs no rebuild.
var _drawn: String = ""

## The single selected piece, or null for any other selection size — the host whose collider
## a hover paints.
##
## SINGLE SELECTION ONLY, matching the other info rows: this row is deliberately
## selection-WIDE (it answers "what standing benefits are in this selection"), but a REACH
## belongs to one piece standing in one place, and painting one arbitrary member's aura for a
## card that speaks for twelve would be a lie about which one.
var _host: Entity = null

## The commander-level node that prices a Warlord's followers, resolved when the cards are
## built rather than per frame — finding it is a subtree search. Null for any other faction.
var _aura_source: AnarchicalDominion = null
#endregion


#region Selection rules
## Every PASSIVE ability this selection makes relevant, in AbilityCatalog order so the row is
## stable as the selection changes rather than following whichever unit was picked first.
##
## Asked of a SELECTION rather than of one piece, and it stays that way even though the row
## now draws only for a single one: it is a pure query, and "what standing benefits are in
## this group" is a question worth being able to ask.
##
## TWO SOURCES, because a passive can be attached to either end of the game:
##
##   * a PIECE that grants it through its own `Abilities` pool — an ability counts when ANY
##     selected piece grants it, so the row answers "what standing benefits are in this
##     selection" rather than "what do all of these share". Duplicates collapse: ten
##     Irregulars carrying one passive draw one card, because the card is about the ability;
##   * the COMMANDER, through a passive cell in its faction's sanction grid. Scavenge is the
##     shipped case — a kill bounty that belongs to the whole army rather than to any piece —
##     so it is relevant to every piece the commander owns, and one of their own being
##     selected is the whole test.
##
## The second source is what makes greying mean something: a passive the faction OFFERS is
## drawn whether or not it has been bought, which is how the player learns it exists. A
## faction with no route to it draws nothing, exactly as the ordnance card does
## (SanctionGrid.has_route_to).
##
## Only the LOCAL commander's own pieces count. An enemy's standing benefits are not the
## player's business, and this row has no way to know them anyway.
static func passives_in(a_selection: Array, a_commander: Commander) -> Array[StringName]:
	if a_commander == null:
		return []
	var held: Dictionary = {}
	var owns_any: bool = false
	# Entity rather than Commandable: ownership and the Abilities pool both live one level up,
	# and a passive is a fact about a PIECE rather than about taking orders.
	for node: Node in a_selection:
		var entity := node as Entity
		if entity == null or entity.commander_id != a_commander.id:
			continue
		owns_any = true
		var pool: Abilities = entity.get_node_or_null("Abilities") as Abilities
		if pool == null:
			continue
		for id: StringName in pool.granted_abilities():
			if AbilityCatalog.is_passive(id):
				held[id] = true
	if owns_any and a_commander.sanction_grid != null:
		for id: StringName in AbilityCatalog.ids():
			if AbilityCatalog.is_passive(id) and a_commander.sanction_grid.has_route_to(id):
				held[id] = true
	var out: Array[StringName] = []
	for id: StringName in AbilityCatalog.ids():
		if held.has(id):
			out.append(id)
	return out


## Whether [a_commander] actually has this passive turned on.
##
## The same question CommandButtonState._is_unlocked asks of an active ability, against the
## STANDING set rather than the deployable one: `deployable_sanctions` and
## `standing_sanctions` partition the owned, non-superseded cells, and a passive is by
## definition in the second. An ability no dominion unlocks is on by owning the piece.
static func is_enabled(a_ability_id: StringName, a_commander: Commander) -> bool:
	if not AbilityCatalog.is_dominion_unlocked(a_ability_id):
		return true
	if a_commander == null or a_commander.sanction_grid == null:
		return false
	for sanction: Sanction in a_commander.sanction_grid.standing_sanctions():
		if sanction.ability_id == a_ability_id:
			return true
	return false


## The stand-in glyph for an ability with no icon: the first letter of its title.
static func letter_for(a_ability_id: StringName) -> String:
	var title: String = AbilityCatalog.title_of(a_ability_id)
	return title.substr(0, 1).to_upper() if not title.is_empty() else "?"


#endregion


#region Public API
## Redraw the row for [a_selection]. Cards are rebuilt only when the SET of passives changes,
## which is the same gate InfoView applies to its own cards; the tint is refreshed every call
## because a passive can be purchased mid-selection.
func update(a_selection: Array, a_commander: Commander) -> void:
	# SINGLE SELECTION ONLY, matching every other row in the panel. `passives_in` still answers
	# for a group — it is a pure query and several callers want that — but the ROW does not
	# draw one: a multi-selection shows its unit cards and nothing else, so the player is
	# looking at WHO is selected rather than at a merged description of them.
	_host = a_selection[0] as Entity if a_selection.size() == 1 else null
	if _host == null:
		visible = false
		return
	var passives: Array[StringName] = passives_in(a_selection, a_commander)
	visible = not passives.is_empty()
	if _signature(passives) != _drawn:
		_drawn = _signature(passives)
		_rebuild(passives)
	# A passive never runs out, so the two live channels are AVAILABILITY — it can be purchased
	# mid-selection, which is the whole reason greying means something — and the RATE, for a
	# passive that produces something.
	for card: Node in get_children():
		var button := card as ConditionCard
		if button == null:
			continue
		var id: StringName = StringName(button.get_meta(&"ability_id"))
		button.refresh(1.0, is_enabled(id, a_commander), _badge_for(id))


## What a producing passive is banking, as a short figure for the card's corner, or "" for
## one that produces nothing — which is every passive but the dominion auras.
##
## The Warlord's figure is what it would bank ON ITS OWN. The sweep may pay less, because a
## follower two Warlords share is paid for once (AnarchicalDominion.followers); subtracting it
## here would make the card unreadable for a rule the player cannot see from this panel.
func _badge_for(a_ability_id: StringName) -> String:
	if a_ability_id != AnarchicalDominion.ABILITY_ID:
		return ""
	var source: Commandable = _host as Commandable
	if _aura_source == null or source == null or not is_instance_valid(source):
		return ""
	# One decimal: the per-follower rate is fractional, so a whole-number badge would round a
	# lone follower's 3.33 down to 3.
	return "+%.1f" % _aura_source.dominion_for(source)


#endregion


#region Private helpers
static func _signature(a_passives: Array[StringName]) -> String:
	var parts: Array[String] = []
	for id: StringName in a_passives:
		parts.append(String(id))
	return "|".join(parts)


func _rebuild(a_passives: Array[StringName]) -> void:
	var host_commandable: Commandable = _host as Commandable
	_aura_source = AnarchicalDominion.for_commander(
		host_commandable.commander if host_commandable != null else null
	)
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	for id: StringName in a_passives:
		add_child(_build_card(id))


## One card. A VerboseTooltipButton because that IS the project's tooltip system — every
## hoverable HUD element goes through it — even though this one does nothing when pressed:
## a passive is a statement, not an option.
func _build_card(a_ability_id: StringName) -> ConditionCard:
	# PERSISTENT, always: a passive does not run out, so its card draws no depletion sweep —
	# which is the channel that tells it apart from a status effect at a glance.
	var button := ConditionCard.build(
		"Passive_%s" % String(a_ability_id),
		letter_for(a_ability_id),
		null,
		AbilityCatalog.valence_of(a_ability_id),
		false
	)
	button.set_meta(&"ability_id", String(a_ability_id))
	var description: String = AbilityCatalog.description_of(a_ability_id)
	button.simple_tooltip = (
		"%s — %s" % [AbilityCatalog.title_of(a_ability_id), description]
		if not description.is_empty()
		else AbilityCatalog.title_of(a_ability_id)
	)
	button.verbose_tooltip = AbilityCatalog.verbose_of(a_ability_id)

	# An aura's card paints the collider the simulation actually sweeps. Only an ability that
	# NAMES a reach asks for one; hovering a card that has none must put the last card's ring
	# away rather than leaving it up.
	var reveals: int = AbilityCatalog.reveals_of(a_ability_id)
	button.mouse_entered.connect(
		func() -> void:
			if reveals >= 0 and _host != null and is_instance_valid(_host):
				ranges_hovered.emit(_host, [reveals])
			else:
				ranges_unhovered.emit()
	)
	button.mouse_exited.connect(func() -> void: ranges_unhovered.emit())

	return button
#endregion
