class_name CommandContextRegistry

## Maps Entity.Type → the CommandContext (the command state machine) available
## to that type of entity. This is the single source of truth the user-facing
## controller consults; CommandReceiver no longer builds contexts and entity
## subclasses no longer override get_command_context().
##
## Built lazily on first lookup: the patterns reference Command subclasses
## (Attack, Train, …) whose script classes resolve in load order, so building
## at static-var init time is fragile. The original CommandReceiver singleton
## was lazy for the same reason.

static var _by_type: Dictionary

## Returns the context for a_type, falling back to the base commandable context
## for any type that isn't specially mapped (generic units, UNDEFINED, etc.).
static func for_type(a_type: Entity.Type) -> CommandContext:
	if _by_type.is_empty():
		_build()
	return _by_type.get(a_type, _by_type[Entity.Type.UNDEFINED])

## The command set every commandable shares: attack a hostile target, otherwise
## issue a plain Command; attack-move and stop sub-contexts.
static func _base() -> CommandContext:
	return CommandContext.new(
		[
			Pattern.new(
				func(a): return (
					a[1].target != null
					and a[1].target is Commandable
					and a[1].target.commander_id != a[0].commander_id
					and Pattern.eval(WeaponPatternsRegistry.for_type(a[0].type), a[1].target) != null
				), Attack
			),
			Pattern.new(func(_a): return true, Command)
		],
		{
			"command_attack_move": CommandContext.new(
				[
					Pattern.new(func(a): return a[1].target != null and a[1].target is Commandable, Attack),
					Pattern.new(func(_a): return true, AttackMove)
				]
			),
			"command_stop": CommandContext.new(
				[Pattern.new(func(_a): return true, Stop)]
			)
		}
	)

static func _build() -> void:
	var base: CommandContext = _base()

	# Structures route tool-bearing input to Train, otherwise a rally Command.
	var structure: CommandContext = CommandContext.new(
		[
			Pattern.new(func(a): return a[1].tool != null, Train),
			Pattern.new(func(_a): return true, Command)
		]
	)

	# Technician (Anima): base set, plus pick up / drop off Stars and the
	# command_ability → Build sub-context.
	var technician: CommandContext = CommandContext.merge(
		base,
		CommandContext.new(
			[
				Pattern.new(func(a): return a[1].target is Star, PickUp),
				Pattern.new(func(a): return (
					!a[0].inventory.is_empty()
					and a[0].inventory[0] is Star
					and a[1].target.type == Entity.Type.STRUCTURE_OUTPOST
				), DropOff)
			],
			{
				"command_ability": CommandContext.new(
					[Pattern.new(func(_a): return true, Build)],
					{}
				)
			}
		)
	)

	# Vanguard: collect from a Lab and the command_launch → Launch sub-context,
	# then the base set.
	var vanguard: CommandContext = CommandContext.merge(
		CommandContext.new(
			[
				Pattern.new(func(a): return a[1].target is Lab, Collect)
			],
			{
				"command_launch": CommandContext.new(
					[Pattern.new(func(_a): return true, Launch)],
					{}
				)
			}
		),
		base
	)

	_by_type = {
		Entity.Type.UNDEFINED: base,
		Entity.Type.STRUCTURE_OUTPOST: structure,
		Entity.Type.STRUCTURE_DWELLING: structure,
		Entity.Type.STRUCTURE_TURRET: structure,
		Entity.Type.STRUCTURE_MINE: CommandContext.NULL,
		Entity.Type.STRUCTURE_LAB: structure,
		Entity.Type.STRUCTURE_COMPOUND: structure,
		Entity.Type.STRUCTURE_ARMORY: structure,
		Entity.Type.UNIT_TECHNICIAN: technician,
		Entity.Type.UNIT_SENTRY: base,
		Entity.Type.UNIT_VANGUARD: vanguard,
	}
