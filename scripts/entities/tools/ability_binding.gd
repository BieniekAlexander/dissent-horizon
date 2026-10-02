class_name AbilityBinding
extends ControlBinding

## An ABILITY's place in the command grid: one button on the ORDNANCE card, built from the
## generated ability catalog rather than authored in code.
##
## The third kind of binding, beside the plain verbs (command_grid.gd) and Tools. It exists
## for the same reason Tool does — the cell, the label and both tooltip tiers all arrive from
## the piece's own doc, so adding an ordnance is writing markdown and re-running the importer,
## with no code or scene edit.
##
## ONE ABILITY CAN BE SEVERAL BINDINGS, all at one cell. A dominion-unlocked ability is armed
## as its own unlocked LEVEL's command ("Scan 1", "Scan 2", "Scan 3" are three commands), and
## supersession guarantees exactly one of them is live at a time — so they are alternatives in
## a cell, which is the rule the grid already applies to every other stacked binding.
## `AbilityCatalog.commands_of` is what enumerates them.

#region Properties
## The ability this button casts. Several bindings may share it (see above).
var ability_id: StringName
## Bitmask of ControlBinding.Faction values, from the doc's `ui.factions`.
var faction: int
#endregion


#region Lifecycle
func _init(
	a_command_name: String,
	a_ability_id: StringName,
	a_label: String,
	a_grid_position: Vector2i,
	a_faction: int,
	a_simple_tooltip: String = "",
	a_verbose_tooltip: String = "",
	a_family: int = CommandFamily.ORDNANCE
) -> void:
	# ACT context always: an ordnance is issued to pieces the way any other command is. The
	# FAMILY is a parameter because an ability may claim a cell on the ACTIVE card as well, and
	# the two cells are different bindings — see _build.
	super(
		a_command_name,
		a_label,
		a_grid_position,
		ControlContext.ACT,
		a_simple_tooltip,
		a_verbose_tooltip,
		a_family
	)
	ability_id = a_ability_id
	faction = a_faction


func faction_mask() -> int:
	return faction


## Every level of one ability is one exclusion group: supersession keeps exactly one of them
## in the commander's hands, so they are alternatives in their shared cell rather than a
## collision. See ControlBinding.exclusion_group.
func exclusion_group() -> StringName:
	return ability_id


#endregion

#region Registry
## Every ordnance button in the game, built once from the catalog.
##
## An ability qualifies iff it authors a CELL. That is the whole test, and it is the same one
## `hud_button:` answers — the importer rejects an ordnance with no `ui.grid`, so a missing
## cell means a LOCAL ability rather than an unfinished ordnance.
static var _bindings: Array = _build()


static func all() -> Array:
	return _bindings


## The ability a grid command casts, or &"" when no binding names it. Answers for a LOCKED
## sanction too, which is what the commander's card needs: it draws every ordnance, and one
## that resolved to no ability could not be told apart from a plain verb and so was never
## greyed. Linear over ~30 bindings and called per visible button rather than per frame.
static func ability_for_command(command_name: String) -> StringName:
	for binding: AbilityBinding in all():
		if binding.command_name == command_name:
			return binding.ability_id
	return &""


static func _build() -> Array:
	var out: Array = []
	for id: StringName in AbilityCatalog.ids():
		var cell: Vector2i = AbilityCatalog.grid_of(id)
		if cell.x < 0:
			continue
		var mask: int = AbilityCatalog.faction_mask_of(id)
		# A cell on the ACTIVE card too, where the ability is also an order you give a selected
		# piece. TWO BINDINGS rather than one carrying both families, because the cells differ:
		# a cell free on one card is spoken for on the other. Same command name, so pressing
		# either does the same thing.
		var active_cell: Vector2i = AbilityCatalog.active_grid_of(id)
		# One button per LEVEL, each carrying that level's own label and copy — see
		# AbilityCatalog.buttons_of for why the words are the level's rather than the ability's.
		for button: Dictionary in AbilityCatalog.buttons_of(id):
			out.append(
				AbilityBinding.new(
					str(button["command"]),
					id,
					str(button["label"]),
					cell,
					mask,
					str(button["description"]),
					str(button["verbose"])
				)
			)
			if active_cell.x >= 0:
				out.append(
					AbilityBinding.new(
						str(button["command"]),
						id,
						str(button["label"]),
						active_cell,
						mask,
						str(button["description"]),
						str(button["verbose"]),
						CommandFamily.ACTIVE
					)
				)
	return out
#endregion
