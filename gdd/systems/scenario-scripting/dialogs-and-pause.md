---
title: Dialogs and pause
type: system-note
---

# Dialogs and pause

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## Pausing the simulation (`SimulationClock`)


`scripts/scenario/simulation_clock.gd`, created by `ScenarioTriggerManager._ready` and reachable as `manager.simulation_clock`. It drives `SceneTree.paused`, which maps exactly onto this game's split: **simulation lives in `_physics_process`** (`Actor._update_state`, the `ProductionQueue` tick, `Fog`, `BotBrain`, `Scenario.frame`), **player agency lives in `_process` / `_unhandled_input`**. So a hold freezes the world while the player can still pan, select, and issue orders — those orders sit in the command queue and are carried out when the world resumes.

Holds are **reason-keyed and counted** (`hold(reason)` / `release(reason)`), because more than one system may want the world stopped at once; the world resumes only when the last hold goes. Nothing "unpauses" — it releases its own hold.

Nodes that must survive a hold declare `process_mode = PROCESS_MODE_ALWAYS` **at their own definition**, not in a list the clock owns:
`RTSController` (and every HUD Control under it), `RTSCamera3D`, `ControlFeedbackSoundPlayer`, `ScenarioTriggerManager` (so the `ConditionPoller` keeps evaluating — that is how a paused beat notices the player did the thing it was waiting for), `ScenarioDialogView`, `ObjectiveView`, `ScenarioHighlight`.

**Careful in headless harnesses**: an in-tree clock pauses the WHOLE tree, GUT included. Tests either keep the clock out of the tree (orphan clocks skip the engine call and only do bookkeeping) or hold and release within one call so no frame elapses. `after_each` should `clear()`.

## Dialog copy lives in PAGE SCENES


Pop-up copy is authored as `DialogPage` scenes under `scenes/dialogs/` — one file per page, referenced by whoever shows it. That exists for REUSE: a tutorial explains the same controls the help book explains, so the copy is written once and a typo is fixed once. Inline text on each event node couldn't be shared and drifted the moment anyone edited one copy.

`DialogPage extends VBoxContainer` with `title` / `body` / `acknowledge_text` / `content_width`, rendering its own labels in `_ready` — so the usual page is "make a scene, fill in three inspector fields". It is a Control rather than a Resource so a page can outgrow three strings: authored child Controls (a diagram, a bindings grid) stack under the body text.

**Specifically a container, and that's what makes the window fit its text.** A container derives its minimum size from its children, so the body's wrapped height propagates out to the `PanelContainer`; a plain Control reports only its own `custom_minimum_size`, so the height never reached the window and it had to guess a fixed one. The page sets `custom_minimum_size` on the X axis ONLY — width is the authored `content_width` (so the window doesn't reflow between beats), height is however much copy there is. `RichTextLabel.fit_content` is the other half: without it the label claims no height.

The page area is a `ScrollContainer` capped at `MAX_PAGE_HEIGHT_RATIO` of the screen (`_fit_page_height`, deferred a frame because a wrapping label's height is only knowable once laid out at its real width). Stretch-to-fit with no ceiling is worse than a fixed height — a long enough page pushes the acknowledge button off the bottom, and a dialog that holds the simulation and can't be dismissed is unrecoverable. Horizontal scrolling is disabled so the page's width still drives the panel.

#### Control prompts are placeholders, never typed-out key names

Write `{{ action_name }}` and `InputPrompt` (`scripts/interface/input_prompt.gd`) substitutes whatever that InputMap action is bound to: `"hold and drag {{ isometric_camera_select }}"` renders as "hold and drag Left Mouse Button". Copy that hardcodes a key goes stale when an action is rebound in `project.godot`, can't survive a rebinding screen, and is **already wrong per-platform** — macOS reports the Alt-bound `modifier_narrow` modifier as "Option", not "Alt".

The swap is a **straight name-for-name substitution that adds no markup**. Styling is the author's: a page that wants the key to stand out writes `[b]{{ isometric_camera_select }}[/b]` and the bold survives around the resolved name (the body is a BBCode RichTextLabel; the title and button are plain Controls, so markup there would show literally).

Resolution happens at RENDER time, in `DialogPage._refresh`: the labels get resolved text while `title` / `body` keep the placeholders they were authored with, so pages re-render correctly if a binding changes. The button goes through `resolved_acknowledge_text()`.

Godot's native equivalent is `String.format(values, "{{ _ }}")`, and the syntax here is deliberately the same so copy stays portable to it. `InputPrompt` uses a `RegEx` instead for two things `format` can't do: it accepts `{{name}}` and `{{ name }}` alike (`format` matches one exact spelling and silently leaves the rest on screen), and it knows which actions were referenced, so a typo is reported rather than shipping literal braces to the player. It composes with `tr()` — translate first, then substitute, so a translator can move the placeholder inside the sentence.

`InputPrompt.action_text()` takes the FIRST event bound to an action (project.godot lists them in authored order, so the first is the primary way to do the thing — `move` is right-click first, `M` second) and uses `as_text_physical_keycode()` for keys, because `InputEvent.as_text()` renders this project's physically-mapped keys as `"A - Physical"`.

## Dialogs (`EventShowDialog` → `ScenarioDialogView`)


`EventShowDialog` points at a page scene and builds a `ScenarioDialog` (a RefCounted request carrying the `PackedScene`), emitted on `ScenarioTriggerManager.dialog_requested`; `ScenarioDialogView` draws it. Same HUD-free indirection as `message_requested`. `EventShowMessage` remains the non-blocking one-liner — though nothing currently authors one, and `Scenario._on_scenario_message` still only `print`s it, so it reaches no player today.

**A win/lose verdict is a bare `EventWinLose` child of the trigger, next to the `EventShowDialog` that announces it.** There is no wrapper scene: `scenes/scenario_events/victory.tscn` used to bundle an `EventWinLose` with an `EventShowMessage`, and it was removed because the message duplicated the sibling dialog (and went nowhere), while the wrapper hid `player_wins` one level down inside an instanced scene — which is exactly how s1's `Defeat` trigger came to announce a *victory* when the player's sapper died. Keeping the flag on the node you can see in the trigger's own children is the point.

**The request carries the scene; the VIEW instantiates.** A request nobody draws then allocates nothing to leak, and the request stays a plain value that can be queued, dropped or re-emitted without owning a Node. The view frees the instance when it moves on; nothing else should hold one.

The **hold belongs to the request, not the window**: `EventShowDialog` takes the `REASON_DIALOG` hold and binds the release to `ScenarioDialog.acknowledged`. A dialog raised in a session that draws no dialogs (spectator, headless test) self-acknowledges rather than freezing the game forever — `dialog_requested` having no connections is the check. Requests queue, and each carries its own hold.

PLANNED: a dialog's dismissal is a recorded order, replayed on the tick it happened — see
[commands/recording-and-replay](../commands/recording-and-replay.md) §Watching.

## The help button (`HelpBook`)


`ScenarioDialogView` is one panel in **two modes**, because both show the same `DialogPage` scenes:

| | Raised by | Navigation | Dismissed by | Hold |
| --- | --- | --- | --- | --- |
| **Event** | `EventShowDialog` | none — one page | acknowledge button | `REASON_DIALOG` |
| **Help** | the HUD help button | ◀ / ▶ through the book | the help button again | `REASON_HELP` |

Distinct hold reasons so closing the book can never release a scripted dialog's hold, or vice versa.

**Event mode takes precedence**: the help button is disabled while a scripted dialog is up, and an incoming dialog closes an open book. A beat that stopped the world to ask something must be answered — letting the book cover it would strand the player behind a window they can't see.

The book is a `HelpBook` node (named `HelpBook`, child of the `Scenario`) listing `PackedScene` pages in reading order; `Scenario._create_scenario_hud` hands it to the view, and a scenario without one has no help button. It is **deliberately unrelated to what the trigger system has raised** — not a log of dialogs seen. It's available from frame one, reads in authored order rather than play order, and doesn't grow duplicates when a trigger repeats. Keeping it consistent with the tutorial's dialogs is an authoring choice; pointing both at one page scene is what makes that cheap. Page stepping **clamps** rather than wrapping, so the end of the book is somewhere you arrive at.
