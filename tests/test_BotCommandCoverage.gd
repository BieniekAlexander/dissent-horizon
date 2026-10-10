extends GutTest

## THE BOT MUST NOT DRIFT AWAY FROM THE CONTROLLER.
##
## Commands are the game's whole action vocabulary, and the bot reaches only part of it.
## That is fine — a bot has no use for some of them — but it must be DELIBERATE, and the
## failure mode this guards is silent: a command is added for the player, nobody asks
## whether a commander would ever want it, and the bot quietly cannot play the part of the
## game it belongs to. Nothing else notices, because the bot's tests all pass.
##
## Every command class is therefore classified below into exactly one of four buckets, and
## the test enforces the classification IN BOTH DIRECTIONS:
##   • a new command that nobody classified fails the run;
##   • an ISSUED claim that the bot does not actually make fails the run;
##   • a NOT_THE_BOTS or MISSING entry that the bot HAS started issuing fails the run,
##     so the table cannot rot into fiction.
##
## Coverage is DETECTED, not declared: the check greps the bot's own source for the
## construction. A table that took the author's word for it would be the same silent
## failure one level up.
##
## The gap list is the point of the exercise, not an embarrassment — see
## gdd/systems/ai/bot-roadmap.md §The gaps in the decision surface.

const COMMANDS_DIR: String = "res://scripts/interface/commands/"
const BOT_DIR: String = "res://scripts/interface/commander/"

## The bot builds and issues these itself, through BotActuator.
const ISSUED: Array = [
	"MoveCommand",
	"AttackMove",
	"Attack",
	"Build",
	"Interact",
	"Occupy",
	"UseSanction",
	"Evacuate",
	"Ability",
	"Spot",
	"Bombard",
]

## The bot causes these WITHOUT constructing the command, each for a stated reason. This
## bucket exists because "does the bot issue X" and "can the bot do X" are different
## questions, and only the second one matters.
const COVERED_OTHERWISE: Dictionary = {
	"Train":
	(
		"submitted straight to Commander.production_queue, so the structure stops reading"
		+ " as idle in the same tick and the bot cannot re-order what it just ordered"
	),
	"Assemble": "Build converts itself to Assemble once the structure exists; nobody orders it",
	"Stop":
	(
		"BotBrain._tick_preservation clears the command with update_commands(null), which"
		+ " is what Stop does"
	),
	"Capture":
	(
		"capturing IS driving over the prey, so the bot issues a move AT it (BotActuator"
		+ ".move_at) — see BotOpportunist's ContactOpportunity"
	),
}

## Commands a commander would never want. Kept short on purpose — every entry here is a
## claim about the game, not about the bot's maturity.
const NOT_THE_BOTS: Dictionary = {
	"SetHoldFire":
	(
		"a player's hold fire queued with the additive modifier. The bot sets the flag itself"
		+ " (BotKamikaze's hold) and never needs it to wait in a queue"
	),
	"FocusFire":
	(
		"a human's manual override of automatic target selection. The bot HAS automatic"
		+ " target selection (BotTargeting) and no hands to override it with"
	),
	"Wander":
	(
		"world behaviour, issued by the Shelter component to loose neutrals. No commander"
		+ " ever orders it"
	),
	"SortieLeg":
	(
		"a called-in aircraft's transit leg, flown by its Sortie component. Nothing orders"
		+ " it; a bot's gunship flies it exactly as a player's does"
	),
}

## KNOWN GAPS — things a commander plausibly wants and this bot cannot do. Enumerated
## rather than discovered, so the cost of each is visible when planning.
const MISSING: Dictionary = {
	"Repair": "no repair decision exists at all; damaged structures stay damaged",
	"Defend":
	(
		"the bot cannot post a unit to hold a region — its only idle answer is to"
		+ " sweep the unit into the attack"
	),
	"Patrol": "the other standing order it cannot give",
	"Land": "no aerial operations at all",
	"Rearm": "no aerial operations at all; a charged clip is never refilled",
	"AirDropRun": "no aerial operations at all",
	"Deploy": "the bot never plants a deploying unit; it fights them as ordinary movers",
	"Undeploy": "and so never has one to pack up",
	"Plant": "the Sapper's charge is never planted",
	"Detonate": "and so never set off",
	"Embark":
	(
		"the bot loads a transport from the passengers' side — an Occupy to each"
		+ " (EscortPolicy) — and never needs the host-side order"
	),
	"Flush": "the bot never storms an enemy-held garrison with a Flusher (the Sleeper)",
	"TaskShelter":
	(
		"the bot hand-drives its Stock Trucks one capture at a time; it never"
		+ " issues the standing order — see gdd/systems/commands/unit-tasking.md §Later"
		+ " consumers, which names the bot's dominion gaps as the same loop"
	),
}


func _read(a_path: String) -> String:
	var file := FileAccess.open(a_path, FileAccess.READ)
	assert_not_null(file, "unreadable: %s" % a_path)
	return file.get_as_text() if file != null else ""


## Every `class_name` declared under the commands directory — the game's action vocabulary
## as it stands right now, read from disk rather than from a list someone maintains.
func _command_class_names() -> Array:
	var names: Array = []
	for file_name: String in DirAccess.get_files_at(COMMANDS_DIR):
		if not file_name.ends_with(".gd"):
			continue
		for line: String in _read(COMMANDS_DIR + file_name).split("\n"):
			if line.begins_with("class_name "):
				names.append(line.substr("class_name ".length()).strip_edges())
				break
	return names


## The text of every bot module, concatenated. Text rather than loaded scripts, on purpose:
## what is asserted is what the source SAYS, and a file that will not parse must fail this
## check rather than vanish from it (see CLAUDE.md on silently skipped test files).
func _bot_source() -> String:
	var source: String = ""
	for file_name: String in DirAccess.get_files_at(BOT_DIR):
		if file_name.begins_with("bot") and file_name.ends_with(".gd"):
			source += _read(BOT_DIR + file_name)
	return source


func _issues(a_source: String, a_command: String) -> bool:
	# "Attack.new(" does not match inside "AttackMove.new(", so the prefix pair is safe.
	return a_source.contains("%s.new(" % a_command)


func test_every_command_is_classified() -> void:
	var classified: Array = ISSUED.duplicate()
	classified.append_array(COVERED_OTHERWISE.keys())
	classified.append_array(NOT_THE_BOTS.keys())
	classified.append_array(MISSING.keys())
	var unclassified: Array = _command_class_names().filter(
		func(n: String): return not classified.has(n)
	)
	assert_eq(
		unclassified,
		[],
		(
			"new command(s) with no stated position on whether the bot should use them —"
			+ " add each to ISSUED, COVERED_OTHERWISE, NOT_THE_BOTS or MISSING"
		)
	)


func test_no_classification_names_a_command_that_no_longer_exists() -> void:
	var existing: Array = _command_class_names()
	var classified: Array = ISSUED.duplicate()
	classified.append_array(COVERED_OTHERWISE.keys())
	classified.append_array(NOT_THE_BOTS.keys())
	classified.append_array(MISSING.keys())
	assert_eq(
		classified.filter(func(n: String): return not existing.has(n)),
		[],
		"classified command(s) that have been renamed or deleted"
	)


func test_every_issued_command_is_actually_issued() -> void:
	var source: String = _bot_source()
	assert_eq(
		ISSUED.filter(func(n: String): return not _issues(source, n)),
		[],
		"claimed as issued but constructed nowhere in the bot"
	)


func test_a_gap_that_has_been_filled_is_not_still_listed_as_a_gap() -> void:
	var source: String = _bot_source()
	var stale: Array = MISSING.keys().filter(func(n: String): return _issues(source, n))
	assert_eq(stale, [], "the bot now issues these — move them to ISSUED")


func test_a_command_ruled_out_has_not_quietly_been_adopted() -> void:
	var source: String = _bot_source()
	var stale: Array = NOT_THE_BOTS.keys().filter(func(n: String): return _issues(source, n))
	assert_eq(
		stale,
		[],
		(
			"ruled out as never useful to a commander, yet the bot issues them — one of the"
			+ " two is wrong"
		)
	)


func test_the_gap_list_does_not_grow_silently() -> void:
	# A RATCHET, not a pin: filling gaps must always be allowed, and adding a command the
	# bot cannot use must be a deliberate edit here rather than a quiet default.
	# Raised 11 -> 12 on 2026-09-17: TaskShelter, added for the Colonial dominion refactor
	# (unit tasking), is a genuine new gap — the bot still hand-drives its trucks.
	# Raised 12 -> 16 on 2026-09-29: Deploy/Undeploy and Plant/Detonate, built for the player;
	# whether the bot should use either is open (gdd/systems/commands/deploying.md,
	# gdd/systems/combat/planted-explosives.md).
	# Lowered 16 -> 13 on 2026-10-07: Ability and Spot are issued (BotAbilities), and Bombard
	# fires on its own at a held beacon. Bombard moved to ISSUED 2026-10-10: the gun's own shot.
	assert_lte(
		MISSING.size(),
		13,
		(
			"more commands the bot cannot use than last time this was reviewed — either wire"
			+ " it up or raise this number on purpose"
		)
	)


func test_the_bot_never_queues_commands() -> void:
	# Queue-building would make the bot decide HOW LONG a plan to build, and that question
	# has no obviously finite answer. Standing orders (Defend, Patrol, a rally point) are
	# the queue-free way to keep a unit busy — see the roadmap's decision-surface gaps.
	assert_false(
		_bot_source().contains("update_commands(cmd, true"),
		"the bot appended to a command queue instead of replacing the command"
	)
