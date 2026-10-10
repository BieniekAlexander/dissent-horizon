---
title: Alerts
type: system-note
---

# Alerts

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**PARTLY BUILT.** The pipeline, the alerts tabled below, throttling, the superweapon global
alert, and a rudimentary toast / sound / jump-key presentation exist. Everything marked
`PLANNED` or `TODO` below does not. Open decisions → [`gdd/tasks.md`](../../../tasks.md) T-102.

An **alert** tells a commander that something happened (an EVENT) or is true (a STATE) that
they would want to act on. Alerts are presentation: nothing here writes to the simulation or
draws from its RNG, so a replay raises exactly the alerts the match did.

---

## The pipeline: everything is raised, a subset is presented

```
sources ──► AlertCenter.raise ──► alert_raised      (every alert, for every commander)
                                    │
                         AlertThrottle (per viewer)
                                    │
                                    ▼
                               alert_presented      (what a player is shown and told)
                                    │
                    AlertFeed (toast + sound + jump history), for the HUD's viewer
```

- **`AlertCenter`** (`scripts/interface/alerts/alert_center.gd`) — one per Scenario
  (`Scenario.alerts()`), built in code like `MatchLog`. It listens to the trigger manager's
  `entity_occurrence` bus for events and polls states and superweapons three times a second.
  It keeps the last 256 raised alerts (`recent()`).
- **An `Alert` is addressed to ONE commander.** One happening raises one alert per commander
  it concerns, because what each may be told — above all, *where* — differs.
- **`AlertCatalog`** is the one table of wording, tone, priority, location rights and throttle
  numbers per type. Retuning "how often am I told my base is under attack" is one row.
- **The presented channel is the bot's too.** [ontology.md §Cues](../../ai/ontology.md) rules
  that a bot perceives only what the presentation presents, and lists a game-wide announcement
  channel with "nothing yet" as its presenter. `alert_presented` is that presenter; no bot
  subscribes yet (`PLANNED`).

## The alerts

| Type | Kind | Who is told | Located? | Source |
|---|---|---|---|---|
| Units under attack | event | the victim's owner | yes | `ON_RECEIVE_DAMAGE` on a `unit` |
| Base under attack | event | the victim's owner | yes | `ON_RECEIVE_DAMAGE` on a `structure` |
| Extractor under attack | event | the victim's owner | yes | the same, on a piece with an `Extractor` |
| Command centre under attack | event | the victim's owner | yes | the same, on a `Deployment.is_command_centre` piece |
| Construction complete | event | the builder's owner | yes | `Commander.construction_finished` |
| Unit ready | event | the producer's owner | yes | `Commander.unit_trained` (`Production._spawn_unit`) |
| Research complete | event | the researcher | no | `Commander.upgrade_researched` |
| Lithium pond depleted | event | the extractor's owner | yes | `WaterBody.drained` |
| Ability charged | event | the caster's owner | yes | polled pools that author `alert: true` |
| Stealthed enemy detected | event | every enemy who can now see it | yes | `ON_EXIT_STEALTH` into `REVEALED` |
| Energy floating | state | the commander | no | polled |
| Infrastructure strained | state | the commander | no | polled `is_infrastructure_strained()` |
| Superweapon begun / built / launched / destroyed | event | everyone but its owner | **never** | polled casters |
| Superweapon ready | event | everyone | owner only | polled caster charges |

**An attack is an enemy's hit, or an unattributed one.** `Entity.receive_damage` writes
`last_hit_by_commander_id` before the occurrence fires; a hit from the victim's own side
(splash, its own strike) is not announced. An unattributed hit (a strike with no firing piece,
an orphaned status effect) is announced, since it is usually the enemy's. Pitfall accepted: a
commander's own Cryogenic Implosion on its own units reads as an attack.
`TODO`: snapshot the firing commander onto `Payload` at launch so attribution survives the
shooter dying.

**The command centre and the extractors are special cases of the base.** Priority runs units 1,
structures 2, extractors 3, command centre 4, so each breaks through a lower hold around it: a
raid on the main announces the base, then the command centre when it is reached. An "extractor"
is any piece with an `Extractor` component — the energy extractor, and the Technocratic Lab that
overlays a site the same way.

**Completions are never held back; they are counted.** Every completion is presented, and a
toast that already says the same words counts it ("Recruit ready ×3"), comes back to the top,
and points its click and the jump key at the newest. A piece's name is its purchase button's
label (`Tool.label`, the doc title), not its node name, which the engine rewrites for a second
piece beside a same-named one.

**A pond is announced once**, on the draw that takes its last energy.

**Ability charged is opt-in per pool.** A pool authors `alert: true` in its piece doc's
`abilities:` entry ([spec importer](../../../../tools/spec_import/README.md)); it is off by
default and on for every structure's pools today. Pools that alert put their `Abilities` node in
`Abilities.ALERTING_GROUP`, the only thing the poll scans. A superweapon's pool is announced as
SUPERWEAPON_READY, not twice.

**Detection is announced, combat-unhiding is not.** A stealthed piece that fights becomes
`UNSTEALTHED` — and its victim is already told it is under attack.
`Stealth._report_transition` fires `ON_EXIT_STEALTH` / `ON_ENTER_STEALTH` on every crossing of
the STEALTHED line; `Entity` had documented these since before they were emitted.

**Floating energy** is spare energy (banked minus what the production queue has promised)
of at least max(1500, 60 s of income), held for 10 s; it clears below 75 % of that line.

## State alerts

A state is polled, so it would speak on every poll. `AlertLatch` speaks once the state has held
for `sustain_seconds`, then every `repeat_seconds` while it holds, and resets the moment it
stops. Hysteresis on the condition (enter at one level, leave at a lower one) is the source's.

## Throttling

The research, and what was taken from it:

| Game | Rule | Taken? |
|---|---|---|
| OpenRA `DamageNotifier` | one per-player cooldown (30 s) for all attack notices; ignores self-damage and unattributed hits; a separate ally notice | the self-fire filter; ally notices `PLANNED` |
| 0 A.D. `AttackDetection` | spatial holds: 60 s, 160 m suppression, 80 m transfer; a higher-priority target breaks through a lower one's hold | **the spatial rule, whole** |
| Beyond All Reason notifications | a per-type delay; at most one of a type per frame; a serial sound queue with a 0.7 s gap; attack notices split by what was hit (commander, factory, economy, defence, units); trivial damage ignored | per-type keyed holds, the sound gap, units/base split |
| OpenRA `SupportPower` | a superweapon's lifecycle as separate notices to owner and others: detected, charge begun, charge ended, launch, incoming; a timer shown per relationship | **the superweapon lifecycle** |

`AlertThrottle`, one per viewer:

- **Spatial** (a type with a `group`): an admitted alert opens a hold at its position. A later
  alert of that group inside `suppress_radius` is swallowed; inside `transfer_radius` it also
  moves the hold to itself and restarts its clock, so one fight that drifts stays one alert. A
  higher-priority alert breaks through and replaces the hold: units under attack, then the
  base behind them.
- **Keyed** (no group, or no position): one hold per (type, key) for `suppress_seconds` — the
  same superweapon announced twice in ten seconds is said once.
- **Temporal, presentation side**: `AlertFeed` plays no sound within 1 s of the last unless the
  new one is louder, and folds a repeat of the newest toast into a "×n" count.

Pitfall accepted: under the 0 A.D. rule a siege that never pauses never re-announces. OpenRA's
plain 30 s cooldown would re-announce it; see T-102.

## Global alerts — the superweapon convention

An ability doc may author **`global_alert: true`**
([spec importer](../../../../tools/spec_import/README.md)). Today only
[Cryogenic Implosion](../../../factions/colonial/sanctions/cryogenic_implosion.md) does. For any
finished caster of such an ability:

- every other commander is told when one is **begun** (foundation laid — a blueprint is
  invisible and is not announced), **built**, **ready**, **launched** and **destroyed**;
- its owner is told when it is **ready**, with its position;
- **nobody else is ever told where.** `Alert.located_at` refuses a position the catalog
  forbids, so a source cannot leak one by mistake;
- every commander sees the **countdown** (`SuperweaponTimers`, top right): one row per built
  caster in its owner's colour, reading its `Abilities.recharge_remaining`, or READY.

It sits on the ability rather than the caster because the strike, not the building, is what
everyone plans around. `TODO`: the timer counts the building's charge whether or not the owner
has bought the tier-4 sanction that lets it fire (T-102).

## Presentation

Rudimentary by design (T-102 lists what a real pass would add).

- **Toasts** (`AlertFeed`) down the left edge below the dominion bar, newest on top, at most
  five, seven seconds each. A located toast is clickable and moves the camera there; an
  unlocated one is plain text.
- **Sound**: synthesised placeholders (`assets/audio/alerts/`, regenerated by
  `tools/alert_sounds/make_alert_sounds.py`): one per `AlertCatalog.Tone`, and one generic
  completion. `PLANNED`: a sound per purchase — `AlertFeed.PURCHASE_SOUNDS`, keyed by the piece
  id an alert carries in `Alert.purchase`, is already consulted first and is empty.
- **Jump key** `camera_jump_to_alert` (Space): the newest located alert; pressed again within
  3 s, the one before, cycling through the last eight (StarCraft II's idiom). Available when
  only watching, too.
- **Perspective**: the HUD shows the local player's alerts, or when spectating or watching a
  replay, the watched commander's — the T-037 item "alerts follow the perspective".

## Tuning

`TODO`: every number in `AlertCatalog` and the floating-energy line is a first guess: 30 s
holds over 30 cells (about a command centre's vision) for attacks, 20 s / 20 cells for
detection, reminders every 60 s (energy) and 45 s (infrastructure).

## Not built — tracked by other games, worth considering

`PLANNED`, none decided:

- **Ally under attack** (OpenRA, BAR) — fixed alliances make this cheap.
- **Unit / structure lost**, distinct from under attack.
- **Idle builders / idle production** (BAR, SC2's idle-worker button).
- **Structure captured / piece stolen** (C&C engineers, Generals) — the Stock Truck and the
  Technocratic infiltrator make this ours.
- **Sanction affordable**.
- **Requisition**: a queued purchase cancelled because what it depended on was aborted (the
  orphaned-transaction question in the control-scheme decisions).
- **Unpowered structures** — the infrastructure alert's consequence named per building.
- **Minimap pings** at each located alert (OpenRA radar pings, 0 A.D. `MinimapPing`).
- **Suppress the sound when the place is on screen** (a common RTS courtesy).
- **Voice lines** in place of tones, and per-alert-type sound.
