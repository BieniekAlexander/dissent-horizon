class_name BotDebugLayer
extends RefCounted

## One category of the bot debug overlay: the signals it draws in the world and the scalars it
## reports as text. The catalogue of categories, and which signals each will carry, is
## gdd/systems/ai/debug-signals.md.
##
## A layer reads the bot and draws; it never writes to it. Everything it draws must be STORED by
## the bot or cheap to derive, because it runs every frame the overlay is up.


## Draw this category's world marks for `a_bot` into `a_pen`.
func draw(_a_bot: Bot, _a_pen: BotDebugPen) -> void:
	pass


## This category's scalar readout for `a_bot`, one line per entry. Run at the overlay's readout
## period rather than every frame, so a derived figure may cost a little more than a mark.
func readout(_a_bot: Bot) -> PackedStringArray:
	return PackedStringArray()


## The bot's brain, or null for a commander without one.
static func brain_of(bot: Bot) -> BotBrain:
	return bot.get_node_or_null("BotBrain") as BotBrain
