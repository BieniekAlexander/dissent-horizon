extends Node

## HUD preview harness for the two PERSISTENT panels a real scenario only reaches after
## minutes of play: the control-group row with groups actually assigned, and the passive
## row with cards on it.
##
## Neither can be seen in an offscreen render of a scenario, and for the same reason: both
## are driven by INPUT that a `--write-movie` run has no way to supply (see CLAUDE.md
## §Offscreen renders and §Seeing the HUD without a screen). So this builds player.tscn
## standalone, assigns groups and a selection directly, and lets the panels draw.
##
## Render it with:
##   godot res://tools/hud_panels_preview.tscn \
##     --write-movie /tmp/hud.png --fixed-fps 30 --quit-after 20 --resolution 1400x790
##
## Flags (after `--`): `--unbought` leaves the passive card greyed, `--unarmed` leaves the
## command card in its ordinary state rather than armed, `--single` selects ONE piece so the
## per-piece info widget row draws (it is drawn for a single selection only), `--afflict`
## puts a status effect on that piece so its condition card draws too, `--holdfire` presses
## hold fire on the selection through the controller, so its condition card, its greyed button
## and its floating badge draw. `--producer` ends with the barracks selected alone, so the
## widget block's production slot and the PRODUCTION card's piece icons draw. `--debug` opens
## the debug menu, so its piece spawner draws. `--cards` adds pieces with charge dials (one
## spent, one weapon reloading) and a part-filled transport to the multi-selection, so the
## unit cards' right-hand columns all draw; `--scrolled` scrolls the summary to its last rows.
## `--deselect` ends with nothing selected, so the global production readout takes the info
## panel's slot.

const PLAYER: PackedScene = preload("res://scenes/player.tscn")
const ANARCHICAL: PackedScene = preload("res://scenes/factions/anarchical.tscn")
## Pieces to squad up and select. Anarchical, because Scavenge — the roster's one PASSIVE —
## is theirs, and the passive row has nothing to draw for any other faction today.
const PIECES: Array[String] = [
	"res://scenes/entities/units/an/an_bioLight_builder.tscn",
	"res://scenes/entities/units/an/technician.tscn",
	"res://scenes/entities/units/an/an_bioMedium_dominionGen.tscn",
]
## Pieces whose cards carry every column, for `--cards`: a Recruit (two ability pools), an
## MLRS (a slow-reloading weapon) and a War Wagon (a garrison).
## Repeated, so the summary fans several of one type into a row.
const CARD_PIECES: Array[String] = [
	"res://scenes/entities/units/cl/cl_bioLight_antiLight.tscn",
	"res://scenes/entities/units/an/an_mechMedium_artillery.tscn",
	"res://scenes/entities/units/an/an_mechStrong_transport.tscn",
	"res://scenes/entities/units/cl/cl_bioLight_antiLight.tscn",
	"res://scenes/entities/units/cl/cl_bioLight_antiLight.tscn",
	"res://scenes/entities/units/cl/cl_bioLight_antiLight.tscn",
	"res://scenes/entities/units/an/an_mechMedium_artillery.tscn",
]
## A producer, so a queued purchase has somewhere it could be made. Without one the queue
## PRUNES the entry as unfulfillable and the rail has nothing to draw.
const PRODUCER: String = "res://scenes/entities/structures/an/an_barracks.tscn"
## Something that producer can actually train — the queue only keeps a purchase it could
## dispatch.
const QUEUED_PIECE: StringName = &"an_bioLight_antiStructure"


func _ready() -> void:
	var player: Commander = PLAYER.instantiate() as Commander
	player.faction_scene = ANARCHICAL
	add_child(player)
	var pieces: Array[Node] = []
	for path: String in PIECES:
		var piece: Commandable = (load(path) as PackedScene).instantiate() as Commandable
		player.add_child(piece)
		piece.ownership.commander = player
		piece.build_progress = 1.0
		pieces.append(piece)
	if "--cards" in OS.get_cmdline_user_args():
		for path: String in CARD_PIECES:
			var extra: Commandable = (load(path) as PackedScene).instantiate() as Commandable
			player.add_child(extra)
			extra.ownership.commander = player
			extra.build_progress = 1.0
			pieces.append(extra)
	_drive(player, pieces)


func _drive(a_player: Commander, a_pieces: Array[Node]) -> void:
	# The controller wires its panels out of its own _ready, and the faction scene lands a
	# frame later still.
	await get_tree().process_frame
	await get_tree().process_frame
	var controller: RTSController = a_player.get_node("Controller") as RTSController

	# Four groups of different sizes, with a gap: 1, 2 and 4 populated and 3 empty, so the
	# visibility rule shows 1–5 and hides the rest.
	controller.selection = a_pieces.duplicate()
	controller.apply_control_group_gesture(0, RTSController.ControlGroupGesture.ASSIGN_GROUP)
	var one: Array[Node] = [a_pieces[0]]
	controller.selection = one
	controller.apply_control_group_gesture(1, RTSController.ControlGroupGesture.ASSIGN_GROUP)
	var two: Array[Node] = [a_pieces[1], a_pieces[2]]
	controller.selection = two
	controller.apply_control_group_gesture(3, RTSController.ControlGroupGesture.ASSIGN_GROUP)

	# Buy the passive so the row draws a LIT card. Pass `--unbought` to leave it greyed, which
	# is the state a fresh commander is actually in.
	if not "--unbought" in OS.get_cmdline_user_args():
		a_player.dominion = 10000
		for entry: SanctionGrid.Entry in a_player.sanction_grid.entries:
			if entry.sanction != null and entry.sanction.passive:
				prints(
					"unlock", entry.sanction.sanction_name, a_player.sanction_grid.try_unlock(entry)
				)

	# A selection is what makes the InfoSection (and so the passive row) visible at all.
	# _refresh_available_commands, because assigning `selection` directly skips the refresh the
	# real selection path runs — and the command card is drawn from available_commands.
	#
	# ONE piece under `--single`: InfoWidgetRow draws for a single selection only, so the
	# multi-select the rest of this harness wants is the one state it never appears in.
	var single: bool = "--single" in OS.get_cmdline_user_args()
	# A status effect is applied by a projectile landing, which an offscreen render has no way
	# to arrange — so it is attached directly. The card only asks the effect what it is.
	#
	# SLOW rather than EMP: the stun effects carry a frame mask and remove themselves on a host
	# outside it (StunStatusEffect._on_apply), so an EMP on the BIO Warlord this harness selects
	# would silently never appear.
	if "--afflict" in OS.get_cmdline_user_args():
		var effect: StatusEffect = (
			(load("res://scenes/entities/status_effects/slow.tscn") as PackedScene).instantiate()
			as StatusEffect
		)
		a_pieces[2].add_child(effect)
		effect.apply_to(a_pieces[2] as Entity)
	if "--cards" in OS.get_cmdline_user_args():
		await _load_card_states(a_pieces)
	controller.selection = [a_pieces[2]] as Array[Node] if single else a_pieces.duplicate()
	controller._refresh_available_commands()
	await get_tree().process_frame
	if "--scrolled" in OS.get_cmdline_user_args():
		# Past the first rows, to where the --cards fans are.
		await get_tree().process_frame
		var cards: ScrollContainer = controller.get_node("InfoSection/Summary/Cards")
		cards.scroll_vertical = int(cards.get_v_scroll_bar().max_value)
	if "--holdfire" in OS.get_cmdline_user_args():
		controller.process_command(CommandContextParser.HOLD_FIRE_COMMAND)
		await get_tree().process_frame
		for piece: Node in controller.selection:
			prints("holding fire:", piece.name, (piece as Commandable).is_holding_fire)
		prints("card shows:", controller._visible_command_names())
	var info: InfoView = controller.get_node("InfoSection") as InfoView
	var widgets: InfoWidgetRow = info.get_node_or_null("Widgets") as InfoWidgetRow
	if widgets != null:
		prints(
			"widget row rect:",
			widgets.get_global_rect(),
			"visible:",
			widgets.is_visible_in_tree(),
			"widgets:",
			widgets.widgets().size()
		)
		for widget: Control in widgets.widgets():
			prints("  ", widget.name, widget.get_global_rect())
	var row: PassiveAbilityRow = info.get_node_or_null("Passives") as PassiveAbilityRow
	prints("passives drawn:", PassiveAbilityRow.passives_in(a_pieces, a_player))
	if row != null:
		prints("passive row rect:", row.get_global_rect(), "visible:", row.is_visible_in_tree())
	var panel: ControlGroupPanel = controller.get_node_or_null("ControlGroups") as ControlGroupPanel
	if panel != null:
		prints("control group rect:", panel.get_global_rect())

	# Queue a few purchases and select one, so the rail draws a chip with the green PENDING
	# border — a state that needs both a queue and a right click, so neither a scenario render
	# nor a headless test can show it. `--nopending` leaves the rail unselected.
	if not "--nopending" in OS.get_cmdline_user_args():
		var producer: Commandable = (load(PRODUCER) as PackedScene).instantiate() as Commandable
		a_player.add_child(producer)
		producer.ownership.commander = a_player
		producer.build_progress = 1.0
		var tool: Tool = Tool.for_id(QUEUED_PIECE)
		if tool != null:
			for i: int in 3:
				a_player.production_queue.submit_train(tool, [], false)
			# And a standing order, so the production readout's third column draws.
			a_player.production_queue.submit_train(tool, [], true)
			var queued: Array = a_player.production_queue.entries.filter(
				func(e: PurchaseTransaction) -> bool: return e.awaits_its_unit()
			)
			prints("entries:", a_player.production_queue.entries.size(), "queued:", queued.size())
			if not queued.is_empty():
				controller.select_pending([queued.back()], false)
			await get_tree().process_frame
			prints("pending selected:", controller.pending_selection.size())
		if "--debug" in OS.get_cmdline_user_args():
			DebugMode.configure(true)
			DebugMode.toggle()
			await get_tree().process_frame
		if "--deselect" in OS.get_cmdline_user_args():
			controller.selection = [] as Array[Node]
			controller._refresh_available_commands()
			await get_tree().process_frame
			return
		if "--producer" in OS.get_cmdline_user_args():
			controller.select_only(producer)
			controller._refresh_available_commands()
			await get_tree().process_frame
			prints("card shows:", controller._visible_command_names())
			return

	# --- PROBE: the two card right-clicks that are hard to reach any other way ------------
	# A garrisoned occupant and an actively-training unit are both drawn only on InfoView's
	# detail cards, and only while their host/producer is the sole selection. Driven here
	# because no headless test can stand player.tscn up (its _ready wants a Map).
	if "--probe-cards" in OS.get_cmdline_user_args():
		await _probe_cards(a_player, controller, a_pieces)
		return  # the probe leaves the HUD in the state it drove it to, for --write-movie

	# Arm an order so the card goes to its READY state — the third card state, which needs an
	# armed command and so cannot be reached by an offscreen render of a scenario either.
	# Pass `--unarmed` to see the ordinary card instead.
	if not "--unarmed" in OS.get_cmdline_user_args():
		controller.process_command("command_attack_move")
		await get_tree().process_frame
		prints("armed:", controller.is_command_armed(), "ready:", controller.is_command_ready())
		prints("card shows:", controller._visible_command_names())


## Put the `--cards` pieces into the states their columns exist to show: a Recruit pool part
## way back, an MLRS mid-reload, a War Wagon holding the Irregular.
func _load_card_states(a_pieces: Array[Node]) -> void:
	await get_tree().physics_frame
	for piece: Node in a_pieces:
		var abilities: Abilities = piece.get_node_or_null("Abilities") as Abilities
		if abilities != null and abilities.pool_count() > 0:
			for id: StringName in abilities.granted_abilities():
				abilities.spend(id)
			for i: int in 20:
				abilities._physics_process(0.0)
		var loadout: Loadout = piece.get_node_or_null("Loadout") as Loadout
		if loadout != null:
			for weapon: Weapon in ChargeDial.dial_weapons(piece as Entity):
				weapon.consume_round()
				weapon.consume_round()
		var garrison: Garrison = piece.get_node_or_null("Garrison") as Garrison
		if garrison != null:
			garrison.garrison(a_pieces[0] as Commandable)
		prints("card piece:", piece.name, (piece as Entity).id)


## Right-click an occupant card and a training card, and report whether the controller's
## selection actually changed. Prints only; this is an instrument, not an assertion.
func _probe_cards(a_player: Commander, a_controller: RTSController, a_pieces: Array) -> void:
	var info: InfoView = a_controller.get_node_or_null("InfoSection") as InfoView
	prints("PROBE info:", info, "controller wired:", info.controller if info != null else "n/a")

	# --- occupant ---------------------------------------------------------------------
	var host: Commandable = a_pieces[0] as Commandable
	var occupant: Commandable = a_pieces[1] as Commandable
	var garrison := Garrison.new()
	# NAMED, because every lookup of it is get_node_or_null("Garrison") — an unnamed
	# Garrison.new() is invisible to the component pattern.
	garrison.name = "Garrison"
	garrison.capacity = 4
	host.add_child(garrison)
	garrison.garrison(occupant)
	a_controller.select_only(host)
	await get_tree().process_frame
	await get_tree().process_frame

	prints(
		"PROBE host.commander_id:",
		host.commander_id,
		"PLAYER_COMMANDER_ID:",
		RTSController.PLAYER_COMMANDER_ID
	)
	prints(
		"PROBE garrison node:",
		host.get_node_or_null("Garrison"),
		"garrison var:",
		host.garrison,
		"occupants:",
		garrison.occupants().size()
	)
	prints(
		"PROBE selection size:",
		a_controller.selection.size(),
		"info visible:",
		info.is_visible_in_tree()
	)
	var details: Node = info.get_node("Details/Cards")
	prints("PROBE detail cards:", details.get_child_count())
	for node: Node in details.get_children():
		var card := node as CommandableCard
		if card == null:
			continue
		prints(
			"  card connections select_requested:",
			card.select_requested.get_connections().size(),
			"pending_selected:",
			card.pending_selected.get_connections().size()
		)
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = true
		card._gui_input(event)
		prints(
			"PROBE immediately after click: selection=",
			a_controller.selection.size(),
			"holds occupant:",
			a_controller.selection.has(occupant),
			"occupant selectable state:",
			occupant.selectable.is_selected(),
			"enabled:",
			occupant.selectable.enabled,
			"by_player:",
			occupant.selectable.selectable_by_player,
			"in_tree:",
			occupant.is_inside_tree()
		)
	await get_tree().process_frame
	prints(
		"PROBE one frame later: selection=",
		a_controller.selection.size(),
		"holds occupant:",
		a_controller.selection.has(occupant)
	)

	# THE ACCEPTANCE TEST: order the selected occupant, then evacuate, and see what it does.
	# Ordered directly rather than through assign_command_to_units: this harness has no Map,
	# and that path stamps terrain height. What is under test here is the RELEASE side.
	var msg := CommandMessage.new(null, null, null, Vector3(42, 0, 42))
	occupant.update_commands(MoveCommand.new(msg))
	prints(
		"PROBE occupant chain after ordering:", occupant.command_receiver.get_command_chain().size()
	)
	garrison.evacuate(a_controller.map)
	await get_tree().process_frame
	var chain: Array = occupant.command_receiver.get_command_chain()
	var dests: Array = []
	for c: MoveCommand in chain:
		dests.append(VU.in_xz(c.message.position))
	prints("PROBE occupant chain after evacuation:", dests)
	prints(
		"PROBE still garrisoned:", occupant.is_garrisoned(), "in tree:", occupant.is_inside_tree()
	)

	# --- the actively-training unit -------------------------------------------------------
	var producer: Commandable = (load(PRODUCER) as PackedScene).instantiate() as Commandable
	a_player.add_child(producer)
	producer.ownership.commander = a_player
	producer.build_progress = 1.0
	var tool: Tool = Tool.for_id(QUEUED_PIECE)
	a_player.energy = 100000
	a_player.production_queue.submit_train(tool, [producer], false)
	a_player.production_queue.tick()
	await get_tree().process_frame
	prints(
		"PROBE producer job_count:",
		producer.production.job_count(),
		"job_transaction:",
		producer.production.job_transaction(0)
	)

	a_controller.select_only(producer)
	await get_tree().process_frame
	# Jobs are drawn in Details only on the PRODUCTION page.
	a_controller.set_command_family(ControlBinding.CommandFamily.PRODUCTION)
	await get_tree().process_frame
	await get_tree().process_frame
	var job_cards: Node = info.get_node("Details/Production/Columns/Producing/ProducingCards")
	prints("PROBE job cards:", job_cards.get_child_count())
	for node: Node in job_cards.get_children():
		var card := node as CommandableCard
		if card == null or card.training_producer() == null:
			continue
		prints(
			"  job card pending_selected connections:",
			card.pending_selected.get_connections().size()
		)
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = true
		card._gui_input(event)
	await get_tree().process_frame
	prints(
		"PROBE pending_selection after training right-click:", a_controller.pending_selection.size()
	)
	prints("PROBE selection after training right-click:", a_controller.selection.size())
	info.update(a_controller.selection, a_player)
	await get_tree().process_frame
	for node: Node in job_cards.get_children():
		var c := node as CommandableCard
		if c == null or c.training_producer() == null:
			continue
		var txn2: PurchaseTransaction = c.training_producer().production.job_transaction(
			c.training_job_index()
		)
		prints(
			"PROBE border check: job_index=",
			c.training_job_index(),
			"txn=",
			txn2,
			"is_pending_selected=",
			a_controller.is_pending_selected(txn2),
			"border child count=",
			c.get_child_count()
		)
		prints("PROBE card rect:", c.get_global_rect())

	# --- the QUEUED unit on the production rail -------------------------------------------
	a_controller.clear_pending_selection()
	a_player.energy = 0  # keep the next purchases PENDING, not dispatched
	for i: int in 3:
		a_player.production_queue.submit_train(tool, [producer], false)
	var rail: ProductionRail = (
		a_controller.get_node_or_null("ProductionSlot/ProductionRail") as ProductionRail
	)
	prints("PROBE rail:", rail, "controller wired:", rail.controller if rail != null else "n/a")
	await get_tree().process_frame
	await get_tree().process_frame
	var chips_found: int = 0
	for holder: Node in [rail.get_node_or_null("%HeadCard"), rail]:
		pass
	for node: Node in _all_cards(rail):
		var card := node as CommandableCard
		if card == null or card.hovered_transaction() == null:
			continue
		chips_found += 1
		prints(
			"  rail card txn:",
			card.hovered_transaction().id,
			"state:",
			card.hovered_transaction().state,
			"pending_selected conns:",
			card.pending_selected.get_connections().size()
		)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_RIGHT
		ev.pressed = true
		card._gui_input(ev)
		break
	prints("PROBE rail chips found:", chips_found)
	await get_tree().process_frame
	prints("PROBE pending_selection after rail right-click:", a_controller.pending_selection.size())
	await get_tree().process_frame
	for node: Node in _all_cards(rail):
		var c2 := node as CommandableCard
		if c2 == null or c2.hovered_transaction() == null:
			continue
		prints(
			"PROBE rail card rect:",
			c2.get_global_rect(),
			"selected:",
			a_controller.is_pending_selected(c2.hovered_transaction())
		)

	if "--probe-hold" in OS.get_cmdline_user_args():
		return  # leave the HUD showing the selected training card, for --write-movie

	# Order the phantom, then run the job to completion and see what the unit does.
	var pmsg := CommandMessage.new(null, null, null, Vector3(77, 0, 77))
	var ordered: bool = a_controller.assign_command_to_pending(MoveCommand, pmsg, false)
	prints("PROBE assign_command_to_pending ->", ordered)
	var txn: PurchaseTransaction = producer.production.job_transaction(0)
	prints("PROBE transaction player_commands:", txn.player_commands.size() if txn != null else -1)

	producer.production.training_queue[0][Production.JOB_REMAINING] = 1
	for i: int in 12:
		producer.production.tick()
		await get_tree().process_frame
	prints("PROBE job_count after ticking:", producer.production.job_count())
	for child: Node in a_player.get_children():
		var made := child as Commandable
		if made != null and made.id == QUEUED_PIECE:
			var spawned_dests: Array = []
			for c: MoveCommand in made.command_receiver.get_command_chain():
				spawned_dests.append(VU.in_xz(c.message.position))
			prints("PROBE spawned unit chain:", spawned_dests)


## Every CommandableCard anywhere under `a_root`.
func _all_cards(a_root: Node) -> Array:
	var out: Array = []
	if a_root == null:
		return out
	for child: Node in a_root.get_children():
		if child is CommandableCard:
			out.append(child)
		out.append_array(_all_cards(child))
	return out
