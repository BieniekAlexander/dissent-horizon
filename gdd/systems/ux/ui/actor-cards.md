---
title: Actor cards
type: system-note
---

# Actor cards

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

The small square card (`CommandableCard`) that stands for one piece: in a multi-selection, as a
garrison occupant, as a training job, and as a chip in the production readout.

## The picture fills the card; two columns sit over its right edge

```
┌─────────────────┐
│              ◐ █│   dial column, top row: one charge dial per queue / pool / slow weapon
│   picture    ◕ █│
│ (whole card)   █│   main column: one vertical bar, filling UPWARD
│              ▮ █│   dial column, bottom row: the garrison bar
└─────────────────┘
```

- **The main column** (rightmost) is the card's one headline figure, as a bar filling from the
  bottom: hit points on a live piece, progress on a training job or a queued purchase.
- **The dial column** beside it is two rows: the **charge dials** on top (§The charge dial) and
  the **garrison bar** beneath — how much of the piece's capacity is occupied, filling upward,
  and hidden while nobody is inside.
- **The columns are drawn OVER the picture**, which always fills the whole card: an empty
  column simply shows the picture through it. Text — the fallback letter, the corner badges —
  keeps left of the columns so a bar never runs through a glyph.
- The geometry is a set of fractions of the card's HEIGHT, so a rail chip is the same card,
  smaller.

## The colour vocabulary

| Where | Colour | Means |
|---|---|---|
| main column | red | hit points |
| main column | blue | a unit in training — progress |
| main column | amber | a purchase being saved for — energy banked against its price |
| main column | green | a purchase paid for, waiting to start |
| garrison bar | green | occupied capacity — the genre's garrison colour |
| charge dial | violet, saturated | a charge held |
| charge dial | violet, half-saturated | the next charge coming back on its own |
| charge dial | violet, near-grey and dim | an empty charge that will NOT come back on its own |
| every track | translucent black | the empty part of a bar or dial |

The card's hit-point red is flat. TODO: the world-space HP bar over a piece is a green →
yellow → red ramp (`HealthBarGradient`) while the card's is always red, so the same figure has
two looks. Options: ramp the card bar too (one idiom, but the card then shows green for health
beside a green garrison bar), or keep the card red (the card is a list of many pieces, where a
uniform colour makes lengths comparable). Kept red pending your call.

## The charge dial

One circle for a **producer's queue**, then one per **ability pool** (abilities that share
charges), then one per **weapon whose payload is slow to come back** — in that order. It is a pie cut into one sector per charge the thing holds — a plain
cooldown is one whole disc:

- a **held** charge is a saturated sector;
- the **next charge coming back** grows clockwise from 12 o'clock across the sector it will
  fill, in the half-saturated hue — saturation is what "yours" looks like;
- an **empty charge nothing is bringing back** is drawn near-grey. Today only a CHARGED weapon
  (rearmed by docking) is ever in this state. TODO: a pool HELD by what it put into play (a
  Sapper's planted charge) is not recharging on its own either; not drawn as stalled yet.

A weapon gets a dial when it is charged, or when its reload takes at least **5 seconds**
(`ChargeDial.WEAPON_MIN_RELOAD_SECONDS`) — the point at which a reload becomes something a
player waits for rather than background cadence. A clip refills whole, so its sweep spans every
empty round at once. A pool whose abilities are all PASSIVE gets no dial: it is never spent, so
it could only ever be full.

A producer's dial is its current job's progress: a sweep that grows to full and starts over,
never becoming a held charge, and an empty track while the producer is idle.

All dials share one hue for now; a dial's place in the column — pools first, then weapons —
says which it is.

### How many fit

The default card fits **three** dials (`CommandableCard.dial_capacity`, derived from the column
geometry), the production queue counted among them. No piece needs more than two today (the
Recruit; the Anarchical and Colonial command centres). Past capacity:

- the **spec importer warns** (never fails) for the piece, when the import is run;
- the **card logs an error** each time it is bound to such a piece and draws only the first
  that fit.

## A multi-selection: one fanned row per type

A multi-selection is drawn as **one row per piece type**, types in the order their first piece
was selected (`InfoView.rows_by_type`). Each row is a fan (`StaggeredCardRow`): the first card
whole, every card after it tucked behind the one before and showing only its two columns plus
a small margin. The stride is the SAME for every card, whether or not its columns hold anything,
so the fan is even and a gap never reads as "this one is different". Clicking any visible part
of a card acts on that piece, as before.

The rows scroll vertically, with the bar on the right, once they outgrow the pane. A type with
more pieces than fit across the pane continues on the next row rather than scrolling sideways.

## Colour collisions: green

Green is now the garrison bar. Everything else in the game that is also green, and whether it
can be confused with it:

| Green elsewhere | Where | Risk |
|---|---|---|
| a funded purchase | the card's main column | same card family, different column; a rail chip has no garrison bar |
| a selected pending purchase's border | rail chips | a border, not a bar |
| full health | the world HP bar's ramp | the closest: a green bar over a healthy piece; never on a card |
| a boon | condition card's top edge | an edge stripe, different panel |
| a purchase in transit | rail glyph `→` | a glyph |
| objectives | scenario highlights, objective checklist | world rings and text |
| an order being drawn | the move-line drag preview | a line in the world |
| team 3 | team tint, minimap | a whole-model tint |
| shelters | minimap cells | minimap only |

TODO: the funded-purchase green and the garrison green share a card family. They never share a
card (a purchase has no occupants), so nothing is ambiguous today; if a card ever shows both,
one of them moves.
