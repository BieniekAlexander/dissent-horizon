---
title: Piece readouts
type: system-note
---

# Piece readouts

What the HUD tells a player about the ONE piece they have selected: the widget row's figures,
the popups behind them, and what `ui_verbose` adds. The row's purpose and order are
[condition-cards](condition-cards.md) §Which row; this note is the depth behind each widget.

## Three tiers

| Tier | Shown | Holds |
|---|---|---|
| **Face** | always, on the widget | the one figure a player glances at mid-fight |
| **Popup** | clicking a widget toggles it; clicking outside closes it | the specifics |
| **Verbose** | while `ui_verbose` is held, inside an open popup | everything else the piece's doc configures |

**Outside verbose, only the weapon widget has a popup.** Every other widget's popup holds
verbose rows alone, so it opens only while `ui_verbose` is held.

**The fields are read from the piece, not from a doc**, so a shipped build with no `gdd/` shows
them. Each field is declared once (`PieceFields`): which component property it reads, its
unit, its tier, and the doc key it is authored under. A field that means nothing for this piece
is not drawn — the air reach of a weapon that cannot hit aircraft, the turn rate of a turret
that is not one. The debug tuning editor
([debug-tuning](debug-tuning.md)) draws the same rows, editable.

## The weapon widget

- **Face:** approximate damage per second, and the damage type. "Approximate" because it is the
  shot's base damage over its firing cycle — no armour, no blast, no misses.
- **Popup:** one card per weapon (a piece may carry several): damage per shot, time between
  shots, clip and reload, startup, reach on each layer.
- **Verbose:** the damage type's multipliers against every armour and frame, and the projectile's
  phases: how each moves, what ends it, what it applies.

## The projectile is reached through its weapon

A projectile has no widget of its own: it is what a weapon does, so it is read under the weapon
that fires it — its name, damage and type, blast, the status effects it applies, whether it is
hitscan; then, verbose, its phases. A projectile several weapons fire appears under each.

## Long readouts fold, and the popup scrolls

A projectile's phases unfolded run to dozens of rows, so every list in a popup folds to its
title: each weapon, its projectile, the projectile's phase list, and each phase (and each ability
pool). A fold is the reader's and outlives the rows — it is not undone by holding `ui_verbose` or
by an edit rebuilding the popup. Phases start open for a player and folded in debug, where each
is twenty editable fields.

The popup grows with its content up to 60% of the screen's height, then scrolls on a bar at its
right edge.

## Figures are numbers, never classes

A speed is shown as world units per second, never as its class name. The speed ladder and the
shape library are an authoring convenience; a player reads distances and rates.
