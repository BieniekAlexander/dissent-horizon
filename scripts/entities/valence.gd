class_name Valence
extends RefCounted

## IS THIS GOOD OR BAD FOR THE PIECE IT IS ON — one word, asked of anything the info panel
## draws as a condition: a status effect acting on a unit, a passive ability it carries.
##
## Its own class rather than an enum on either of them, because BOTH need it and neither owns
## the other: `StatusEffect` is a gameplay node and `AbilityCatalog` is authored data, and
## putting the vocabulary on one would make the other depend on it. Nothing here knows what a
## card looks like either — the HUD reads this and decides; see ConditionCard.
##
## THREE VALUES, NOT A BOOL. NEUTRAL is not "we forgot": a condition can genuinely be neither
## (a marker, a state that only matters in context), and forcing such a thing to claim it is
## good or bad puts a green or red edge on a card that means neither. It is also the safe
## default for a condition whose author has not decided.

enum Kind { NEUTRAL, BOON, BANE }

## The accent each valence is drawn in. Deliberately not the pure red/green a colour-blind
## player cannot separate: the shipped pair differ in LIGHTNESS as well as hue, and the card
## carries a second, non-colour channel besides (see ConditionCard.EDGE_HEIGHT — a boon's
## edge sits at the TOP of the card and a bane's at the BOTTOM).
const COLORS: Dictionary = {
	Kind.NEUTRAL: Color(0.62, 0.64, 0.66),
	Kind.BOON: Color(0.56, 0.86, 0.52),
	Kind.BANE: Color(0.92, 0.42, 0.40),
}

## Reader-facing names, for tooltips and for anything that lists the set.
const TITLES: Dictionary = {
	Kind.NEUTRAL: "",
	Kind.BOON: "benefit",
	Kind.BANE: "affliction",
}


static func color_of(a_kind: Kind) -> Color:
	return COLORS.get(a_kind, COLORS[Kind.NEUTRAL])


## The enum spelling a doc uses (`valence: BOON`), or NEUTRAL for an absent or unknown value.
## Permissive because validation is the importer's job: a HUD that fell over on a typo would
## be worse than a card with no accent.
static func from_name(a_name: String) -> Kind:
	var key: String = a_name.to_upper()
	return int(Kind[key]) if Kind.has(key) else Kind.NEUTRAL
