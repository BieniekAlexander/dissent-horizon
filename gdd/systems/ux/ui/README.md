---
title: UI
type: system-index
---

# UI

The interface half of [UX](../README.md): what the player sees and touches.

| Note | Covers |
|---|---|
| [interface-idioms.md](interface-idioms.md) | what the control scheme commits to, as idioms rather than a keymap: what each modifier is for, the fixed constraints, the open tensions |
| [selection-and-input.md](selection-and-input.md) | `RTSController`, input actions, box-select drags, two-tier tooltips |
| [hud-layout.md](hud-layout.md) | the persistent/selection-owned split, where production is shown, economy stack, selectors |
| [command-card-and-hotkeys.md](command-card-and-hotkeys.md) | the two command cards, positional grid keying, the selector matrix |
| [cursor.md](cursor.md) | the cursor's five images, which shows when, and why the OS keeps losing it |
| [control-matrices.md](control-matrices.md) | every controller context × button × modifier, and which cells are unused |
| [input-action-naming.md](input-action-naming.md) | what an action-name prefix means, and the proposed renaming (not executed) |
| [construction-visuals.md](construction-visuals.md) | the opacity and shade channels that say how real a structure is |
| [condition-visuals.md](condition-visuals.md) | `StatusVisuals`: effect tints, floating badges, veterancy, capacity pips |
| [range-reveal.md](range-reveal.md) | rings on the ground: hovered info cards, and what an armed ability would cover |
| [condition-cards.md](condition-cards.md) | status effects and passives as one card: valence, duration and availability |
| [piece-readouts.md](piece-readouts.md) | the depth behind the selected piece's widgets: popups, the verbose tier, the weapon card |
| [debug-mode.md](debug-mode.md) | the debug view and menu: piece spawner, delete, commanding any piece, swapping player |
| [debug-tuning.md](debug-tuning.md) | editing a piece's doc values live in debug mode, the library menu, and saving to the docs |
| [generated-visual-defaults.md](generated-visual-defaults.md) | placeholder meshes, derived selection shapes and HP bars; the clearing protocol |
| [actor-cards.md](actor-cards.md) | the unit card: picture, HP and garrison columns, charge dials, its colour vocabulary; the multi-selection's fanned rows |
| [menus.md](menus.md) | the title screen's pages, the skirmish lobby, and the recipe a lobby match and its replay are built from |
| [piece-icons.md](piece-icons.md) | the picture a unit or structure is drawn as on the HUD; the stock-photo placeholders |

**Belongs here:** panels and buttons, input actions and key bindings, cursor behaviour,
tooltips, minimap, and how any game state is *drawn*.

**Does not belong here:** what a button's command actually does ([commands](../../commands/)),
and mission dialogs and objective checklists
([scenario-scripting/dialogs-and-pause](../../scenario-scripting/dialogs-and-pause.md)) — those
are authored per mission rather than part of the standing HUD.
