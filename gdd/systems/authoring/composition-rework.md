---
title: Composition rework — plan
type: system-note
status: plan
---

# Composition rework — plan

*Design note for [Dissent Horizon](../../../CLAUDE.md).*

**TODO — the rest of step 4.** Steps 0–3 and 5 are built, and step 4's scene composition is
built (2026-09-25); §Step 4 lists what of it remains. §Step 0 records what its acceptance could
not yet demonstrate. It is the agreed direction for
two tasks that turn out to be one — the entity component model ("Bugs", option 3) and the
projectile redesign ("Revisiting Projectile System") — and it exists so that one agent can
execute them together. **The words for what a piece IS are defined in [piece-vocabulary](piece-vocabulary.md),
settled 2026-09-18. This note was written before then and uses "structure" for anything
with a footprint. Read that as *fixture*: under the settled vocabulary a structure is a
commandable fixture; the `"structure"` group this note discusses was split into `"fixture"` and
`"structure"` at step 4.** Where it contradicts a rule stated elsewhere, the other note is what
ships today and this note is what supersedes it; each such place is named below.

---

## Why these are one task

Two design passes, written independently, arrived at the same sentence:

> **Under scene inheritance, the presence of a node can never be a predicate.**

[projectiles](../combat/projectiles.md) reached it from the emission side: `projectile.tscn`
hands a `HitShape` to every scene that inherits it, Godot cannot remove an inherited node, and
so `hit_shape != null` is unanswerable — asserting on it crashed six shipped pieces on their
first shot, and `hitscan` had to be made authoritative over it.
[entity-scene-hierarchy](entity-scene-hierarchy.md) reached it from the piece side: a scene
inherits from exactly one base, so "a piece with both `Structure` and `Movement`" cannot be
expressed, and "a piece with no model" can only be expressed by refusing to inherit anything
at all — which three scenes in the roster already do.

They are the same defect. **Fixing it twice would produce two vocabularies for one idea**, and
a third is already in play: the id convention (`<faction>_<frame><Armour>_<role>`) states a
piece's role in its NAME, which is the same classification `kind:` states in frontmatter and
the base scene states in the tree. Three places to say one thing, and they can disagree.

The target is one statement, in the doc: **what a piece is composed of.** Its role, its base
class, its groups, its folder and its name follow from that rather than deciding it.

---

## What is being retired

Named explicitly, because each is a rule written down somewhere and a reader will otherwise
find two answers.

| Retired | Where it is currently stated | Replaced by |
|---|---|---|
| "Guaranteed = on the base scene for its kind" | [entity-scene-hierarchy](entity-scene-hierarchy.md) §The proposed contract | guaranteed = the doc asked for it; validated at import AND at load |
| `kind:` **as a classifier** (the key itself survives) | `tools/spec_import/README.md` §Doc schema | `kind:` names the CLASS loaded (`kind: Entity`); role is derived from composition |
| `unit.tscn` / `abstract_structure.tscn` / `projectile.tscn` as inherited bases | scene tree | a root body scene per BODY TYPE, plus a component library |
| Two-phase `IN_FLIGHT` / `POST_IMPACT` | [projectiles](../combat/projectiles.md) §Payload schedule | an ordered phase list of arbitrary length |
| `Trajectory` as a four-member enum | `Projectile.Trajectory` | three motion scalars, with the four names surviving as import-time presets |
| `hitscan` as one boolean | `Projectile.hitscan` | impact test and payload aiming, separately |

**Not retired: `MeshVisual` on `commandable.tscn`.** That was option 2 of the previous
question and it stays — one declaration of one universal fact is correct under composition
too; it simply becomes "the importer gives every piece a `MeshVisual`" rather than "every
piece inherits one". The `index=` semantics recorded in
[entity-scene-hierarchy](entity-scene-hierarchy.md) §Moving a node between bases stay true and
stay useful right up until step 5 removes the inheritance they describe.

### `MeshVisual` is default-on, and the opt-out removes as well as refuses

The doc does not ask for a visual; it asks NOT to have one. A `MeshVisual` is created for
every piece, and where the piece has no art the generated-visual-defaults pass supplies a
placeholder — that is already what it does, and it is why a new doc looks like something
the moment it imports. What changes is that the exception becomes authorable: a piece that
should carry no mesh at all (the bodiless fog pseudo-unit below, a pure trigger volume)
declares it, and the pass then **removes any mesh that is already there** rather than
merely declining to add one.

**That removal is the whole point of naming it here, and it is step 0's contract, not a
second one.** A pass that only adds converges from one direction: clearing the exception
puts a mesh back, but declaring it leaves the old mesh in place forever, and the scene
stops meaning what the doc says. Removal is what makes the pass idempotent in both
directions — see §Step 0, which is where that guarantee is built and tested for every
component; the visual pass inherits it rather than restating it.

Built as answered: `exceptions: {has_mesh_visual: "<why>"}`, which goes `STALE` once the scene
holds authored art — the rule reads a scene view the registry builds only for docs declaring
it. `visual:` is refused.

---

## The target model

### One statement per piece

A doc declares a **component set** and the values each component carries. Nothing else
classifies the piece:

- **Role is derived.** A doc with a `footprint:` occupies terrain, therefore it is a
  structure. A doc with `movement:` can be driven, therefore it is a unit. A doc with both is
  a piece that transforms between the two. A doc with neither is a bodiless entity.
- **Groups are derived and WRITTEN, not inherited.** `"unit"` / `"structure"` /
  `"piece"` / `"los"` come from the same derivation and are written into the scene by
  the importer. This matters: those groups live on the base scenes today, so dissolving the
  bases removes the mechanism that supplies them, and ~33 call sites read them.
- **The base class is derived** from whether the piece needs a physics body at all, not from
  what it does.

### Three tiers, re-founded

The tier vocabulary survives; what founds it changes. It stops being "which base scene you
inherit" and becomes "what the doc asked for":

| Tier | New rule | What it licenses |
|---|---|---|
| **Guaranteed** | the derivation ALWAYS creates it for a piece of this composition | `$Node`, no null check |
| **Optional** | created iff the doc names its key | `get_node_or_null`, callers gate |
| **Identity** | one piece, or a named handful; states what that piece IS | resolved by the mechanic that owns it |

`get-node-or-null-audit.md` has to be re-verdicted against this, because "optional" changes
meaning: today it means "some base scenes lack it", afterwards it means "the doc did not ask
for it". Several of its current verdicts are answers to the old question.

### Activation, for components that own external registrations

Some components hold state outside themselves: `Structure` owns grid cells and a navmesh hole,
`Movement` owns a nav agent and an avoidance entry. Those gain an **active/inactive** axis so
that two mutually-exclusive components can coexist on one piece with exactly one live.

**Not every component needs this.** A component with no external registration (`Defense`,
`Loadout`) is inert when unused and gains nothing from a flag. Activation is a capability of
the components that register something, and the plan should add it to exactly those.

### Which form a piece spawns in

A piece carrying both `footprint:` and `movement:` has two bodies and exactly one may be
live. Something has to say which, at the moment the piece comes into existence. The two
motivating shapes are opposite: Red Alert 3's Sputnik is **trained** and enters mobile,
deploying into a structure later; Warcraft 3's Ancients are **built** as structures and
unroot into units. So the answer plainly correlates with what created the piece — and the
question is whether that correlation is the whole rule, or whether the doc must also carry
an initial-state key.

**Decided: the spawn site decides the form, and the doc carries no initial-state key.** The
doc says what the piece is MADE OF; the site that instantiates it says which form it stands
up in, exactly as it already hands an emitted rocket a motion and an emitted unit a command
(§Emitting, as one interface). Initial form is one more kind of *initial intent*, so it
needs no new plumbing and no new key.

**What makes that more than a convenient default: `Build` cannot honour any other answer.**
A build order reserves footprint cells, punches a navmesh hole and runs `Assemble` against a
static site; construction *is* a terrain-grid occupation. There is no coherent "build a
moving thing in place", so a doc that claimed `starts_as: UNIT` would simply be overruled
for the whole time the piece was under construction. A key that the dominant origin has to
ignore is a key that lies, and it would be the fourth place to state one fact — which is the
defect this plan exists to remove.

Three rules follow, and together they cover every case:

1. **`Build` spawns the deployed form.** Not a preference; a precondition of construction.
2. **Every other site names the form it wants** — `Train`, a sanction drop, an emitter, a
   garrison evacuation, an internment, scenario `init.json` placement. **A site with no
   opinion gets the MOBILE form**, because that is the form with no external registration to
   reconcile: a piece that starts mobile can deploy later by finding a legal footprint,
   whereas a piece that starts deployed onto cells nobody validated is grid corruption. The
   invariant worth stating outright is that **the deployed form is only ever entered through
   a path that validated a footprint** — which is equally true of the transform ability, and
   is why deploying into an occupied cell must be refused the way a build placement is.
3. **The doc carries only what the origin genuinely cannot know: what happens when
   construction finishes.** That is the case the origin rule does not cover — a piece raised
   by a build order that is meant to walk away once the scaffolding comes off. It is a
   behaviour, not an initial state, and it belongs in the nest that owns the build
   transaction: `build.completes_as: UNIT`, defaulting to keeping the deployed form. See
   [spec-importer](spec-importer.md) §The doc's shape.

The transform itself stays what §The transformer describes — an ability that flips the
activation switch, with no respawn and no loss of HP, veterancy or orders. `completes_as` is
that same switch, thrown once, by construction completion instead of by an order.

### Emissions

Built at step 2 — an emission is an ordered phase list; [projectiles](../combat/projectiles.md)
§Phases is the model and its doc grammar.

### Emitting, as one interface

Every spawn site in the game already does the same three steps: instantiate a scene,
initialise it against an owner, hand it its initial intent. `Weapon.fire`, `Bombard`,
`Ability`, `Interact`, `Build`, and eleven `scenario/events/*` classes each re-implement them.

One **emitter** interface over those three steps is what makes the Brood Lord possible without
the emission class ever learning that units exist: what changes between an emitted rocket and
an emitted unit is only which composition is instantiated and what "initial intent" means (a
motion, or a command).

---

## The name

**Decided 2026-09-25: there is no `Emission` type.** An emission is an ORIGIN, not a noun
([piece-vocabulary](piece-vocabulary.md) §Emission is an origin): a piece an emitter put into the
world, whose type is already fixed by the vocabulary. The emitter side is named — the `Emitter`
interface and the `emits:` key — and code may call the thing it emits `emission` as a variable,
but never as a class.

**Everything a weapon emits is a figure** — a token (a rocket, a cloud) or a unit (a broodling) —
because it has to move through space rather than sit on the terrain grid. Other actions can
leave fixtures behind (a build order does), and whether those count as emissions depends on how
far the word is stretched; for weapons the answer is fixed.

REJECTED — renaming `Projectile` to `Emission`, `Munition`, `Payload` or `Effect`. `Emission`
would have made an origin into a class; the others were narrower or already taken.

**Built 2026-09-25: the `Projectile` class dissolved with the shared locomotion core**
(§Locomotion is bigger than `Movement`). A rocket is an ordinary `Entity` carrying a phase-list
locomotion and a payload component, its doc says `kind: Entity`, and nothing needed a new name.

---

## What replaces `kind:`

`kind:` currently does two unrelated jobs, and only one of them is being retired.

**Job 1 — discovery.** "A markdown file is a spec if and only if its frontmatter names a
`kind`." This job is load-bearing and has no replacement in composition: `gdd/` is an Obsidian
vault full of prose (this note included), doc LOCATION is deliberately organizational, and
validation is meant to be total and loud. Something must still say "this file is a spec".

**Job 2 — classification.** Selecting a validator, a base scene and a home directory. This is
the job that pigeonholes, and this is the one that goes.

**DECIDED: `kind:` stays, and names the Godot class the spec loads as.** Not a bare marker and
not a keyless heuristic — the key survives, and its value stops being a game-design category
(`unit`, `structure`, `projectile`) and becomes the CLASS being imported, spelled the way the
class is spelled: `kind: Entity` for every game piece, `kind: Faction` for a faction. Alex's
words: *"let `kind` indicate that the spec defines something to be imported into Godot, and
let the value indicate the class of thing being loaded, and use the proper capitalization to
comport with the class naming."*

That is a better answer than any of the three offered, and worth understanding rather than
just following. The objection was never to having a key — it was to the key deciding what the
piece IS. `kind: Entity` decides nothing about the piece: every game piece is an `Entity`, so
the value carries no classification to disagree with the composition, and discovery stays
exactly as total and loud as it is today. It also stops the vocabulary forking, which the
bare-marker option would have done: `spec: true` would have left the importer with a marker
that says "this is a spec" and no word at all for what it becomes.

Two consequences to carry into the migration:

- **The value tracks the CLASS, so it moves when the class does.** Emission docs said
  `kind: Projectile` until that class dissolved (§The name); they now say `kind: Entity`. The value
  is a load target, not a taxonomy.
- **`PascalCase` is now meaningful in the schema**, where every other enum-ish value is
  `SCREAMING_SNAKE` (`armour: MEDIUM`) or lowercase. That is the point — it is spelled like the
  class because it names the class — but the validator should say so when it rejects
  `kind: entity`, or the casing rule reads as a typo hunt.

Role itself comes from the discriminating keys below.

### The discriminating keys

| Key present                                        | Derives                                                                                      |
| -------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `footprint:` (terrain-grid occupation)             | occupies the grid → `Structure`, the `"structure"` group, footprint-adjacent command routing |
| `movement:`                                        | can be driven → `Movement`, the `"unit"` group, nav agent + avoidance                        |
| `phases:`                                          | a token moved by its phase list → a `PhasedLocomotion` and a `Payload` on an `Entity` root, no command queue, no selection |
| `vision:`                                          | contributes fog reveal → `VisionRange`, the `"los"` group                                    |
| `applies:` / effect keys with no body of their own | a status effect                                                                              |
| `sanctions:` on a faction doc                      | a faction                                                                                    |

Two forward notes on that table, so it is not read as final. **`movement:` is a weaker
discriminator than it looks** — §Locomotion is bigger than `Movement` separates "moves" from
"the player drives it", and the `"unit"` group follows the latter. And **some of these key
PATHS move** under [spec-importer](spec-importer.md) §The doc's shape (`vision:` becomes
`senses.vision`); what each key discriminates is unaffected by where it sits.

**Several is legal, and is the point.** `footprint:` + `movement:` is the transformer, and it
validates.

**None is an error, loudly.** A doc that satisfies no discriminator is either prose that
should not carry the marker, or a piece whose author forgot the key that gives it a body.
Both are authoring mistakes and both should abort the import, in keeping with the existing
"validation is total and loud, nothing is written" rule.

**Ambiguous pairs get a stated precedence, not a guess.** `phases:` together with `movement:`
is refused rather than resolved: an emission that also wants a command queue is a
`Commandable` that a weapon emitted, which the emitter interface already covers.

### The doc's SHAPE is part of the model, not decoration

Two properties are asked of the schema alongside the discrimination above, and they are one
deliverable rather than two: **a universal key order** so that specs read side by side, and
**more nesting** so the outline says something. The nesting IS the order, because a doc is
read top to bottom.

**The shape shipped in step 0** and is [spec-importer](spec-importer.md) §The doc's shape,
with `SpecSchema` as its code. Its organising rule and its position on order:

- **One top-level key per component; its sub-keys are that component's authored values.**
  That is this plan's own thesis applied to the page — if the doc declares a component set,
  the doc's outline should BE the component set, and "which keys are present" is already the
  discrimination above. Its four real nests are `build:` (`cost` / `time` / `requires`, the
  worked example from the ask), `defense:`, `senses:` and `body:`; the discriminating keys
  stay flat, because they are already one key per component and an indent would only push
  them further from the eye that scans for them.
- **Order is never a validation failure.** A spec whose keys are out of order imports
  normally and the importer **rewrites the frontmatter into canonical order in the file**,
  in the pass that already writes an inferred `scene:` back. The rewrite is held to step 0's
  contract in another file format: idempotent (reordering an ordered doc changes no bytes),
  total (unknown keys sort to the end rather than being dropped), and value-preserving
  (block scalars and wikilinks round-trip). It races Obsidian Sync exactly as the task file
  does, which is the argument for doing it in the existing doc-writing pass rather than a
  second visit.

### Locomotion is bigger than `Movement`

`Movement` currently means two things at once: **that a thing moves**, and **that a
navigation agent and an RVO avoidance entry decide how**. Three cases in the plan already
want the first without the second:

- an emission in flight has a position, a destination and a trajectory, and consults neither
  navmesh nor RVO;
- a piece whose motion the player cannot influence — a train on a scripted track, carrying a
  commandable cannon that takes attack orders from its owner;
- a deployed transformer, which still has a position but must not hold a nav agent.

So the shared core is small and real: **a current position, a desired destination, and the
configuration that turns one into the other.** Nav-agent-plus-avoidance is one strategy over
that core; an emission's phase motion is another; a scripted track is a third. That is worth
adopting as the direction, with two consequences to state now rather than discover:

- **`movement:` stops being a safe discriminator for "unit".** A train has locomotion and no
  player agency; a deployed Sputnik has agency and no locomotion this tick. What the
  `"unit"` group and the command grid actually want is the next section's question, not this
  one.
- **It widens §Blast radius's largest row.** ~167 `movement != null` sites currently mean
  three different things — "can this thing move at all", "is it mobile right now", "is there
  a nav agent to talk to" — and a shared core is what lets them stop being one spelling.

#### The design (decided 2026-09-25)

**`Locomotion` holds a GOAL and decides what to do with it.** The interface is not a set of
orders (move, pursue, stop). Whatever drives the piece sets a goal — a position, an entity, or
none — and asks back whether it is moving and whether it has arrived. Locomotion does not know
or care whether the goal was set once by an emitter or is rewritten every tick by a command.

**Each STRATEGY decides what a goal means**, and a goal it cannot act on is still accepted:

| Strategy | Moves by | With nowhere to go | Avoidance |
|---|---|---|---|
| **Navigated** | navmesh path toward the goal | stops | yes (RVO) |
| **Immobile** | nothing — the goal is accepted and ignored, for interface consistency | is already stopped | no |
| **Phased** | the emission phase list: launch solve, steering, gravity, end clauses | cannot stop (see below) | no |
| **Tracked** | a scripted path (the train) — not built | per its track | no |

**A phased mover cannot stop.** If a homing missile's target leaves the game, it takes the
target's last position as a fixed goal and loops around it until it expires or collides with
something.

**Avoidance belongs to the strategy**, never to the interface: a navigated mover avoids, the
others do not.

**Flight and height are a separate `Aerial` component**, not part of locomotion. It owns
altitude (hovering and flying height), landing and take-off, deck state and the taxi, dives and
orbiting. Locomotion keeps horizontal goal-seeking; when a landing, a taxi or a climb-out has to
move the piece itself, `Aerial` drives the locomotion's velocity through a narrow interface
(`Movement` §Aerial drive). That makes "is this airborne" the presence and state of `Aerial`.

Two things the design named stayed where they were. **Parachute descent stays on `Movement`**:
it is a state of a GROUNDED unit, and a piece that does not fly has no `Aerial` to carry it.
**The Recon Drone keeps its speed-0 `Movement`** beside its `Aerial` (decided 2026-09-29): it
only has to hold a hovering position, and it never receives an order that would move it.
REJECTED: an `Aerial` with no locomotion — it would stop the drone being mobile to
composition, changing its body, groups and collision, for no behaviour anyone needs.

**Docking is its own abstraction, `Docking`: "where is my dock?"** It is the unit-side half of
`DockingBay`/`DockingPad` — the pad it stands on, the runway it holds, leaving the dock, and going
home to rearm — and its presence is whether a piece docks at all. It is shaped for aircraft now,
because that is the only use: "arrived at the dock" is asked of the piece's `Aerial`, and the
importer refuses `docking:` without `aerial:` (TODO — ground units that dock are planned, and
need an arrival of their own).

**The three meanings of `movement != null`** become three questions: can this piece move at all
(it has locomotion that is not immobile), is it moving now, and does it have a nav agent (only
code that genuinely talks to the navigated strategy asks that).

#### Order

1. A `Locomotion` base with the goal interface. `Movement` becomes the navigated strategy
   underneath it, unchanged, and callers begin to use the interface. **Built 2026-09-25**:
   `scripts/entities/components/locomotion.gd`; the goal is a position, an `Arrival` (stop or
   pass through) and an optional pursued piece; `tick` reports MOVING / ARRIVED / HOLDING, and
   `arrive`, `stop` and `settle` replace the steering the receiver used to do itself.
   Accepted by per-tick position traces (`run_sims.tscn … trace=`) of queued ground moves,
   following, hovering waypoints, flight, a flying attack and attack-move: identical to the
   baseline, or divergent only at the scattered frames where identical baseline runs diverge
   from each other (the avoidance-thread race).
2. The phase motion moves out of `Projectile` into a phased strategy; `tools/emission_trace.tscn`
   proves flight and damage unchanged. **Built 2026-09-25**: `PhasedLocomotion`
   (`scripts/entities/components/phased_locomotion.gd`) owns the phase sequence, the motion and
   the end clauses. Every emission scene carries it as a guaranteed component (`SpecComposition.EMISSION_COMPONENTS`).
   The trace, which now also records every emission's position on every tick, is byte-identical.
   The lost-pursuit rule is new behaviour — see [projectiles](../combat/projectiles.md) §A lost
   pursuit loops.
3. The `movement` sites get their verdicts, and the emission class dissolves. **Built
   2026-09-25.** An emission is an `Entity` with a `PhasedLocomotion`, a `Payload` (damage,
   aiming, effects, what a contact means) and optionally a `Tracer` (the beam); every emitter
   launches one through `Emitter.launch`, and its doc says `kind: Entity` (`kind: Projectile` is
   retired). The verdicts: "can this move?" asks `can_move()`; stopping, settling, arriving and
   holding still go through `locomotion` (the command tick, stun, freeze, an attacker turning to
   aim, a waypoint chain); everything else that reads `movement` genuinely talks to the navigated
   strategy — facing, the nav target and class, avoidance, speed — or to flight and docking, which
   step 4 moves. Accepted by the emission trace (byte-identical) and the unit traces.
4. `Aerial` and `Docking` come out of `Movement` and `Commandable`, and the call sites move once,
   to their final home. **Built 2026-09-26**, on Alex's two answers: the flight values have their
   own key (`aerial: {mode, orbit_radius, orbit_speed}`, per the one-key-per-component rule), and
   docking is DECLARED (`docking: true`), not derived from flying. Every aircraft doc was migrated
   to keep what it did: its mode and orbit moved to `aerial:`, and it gained `docking: true` unless
   it had said `docks: false`; `movement.mode` and friends are refused with a pointer. `Aerial`
   sits straight after `Locomotion` so it ticks where the flight code did; `Movement.mode` is now
   read off it (GROUNDED when absent). Found on the way: `SpecComposition.tier` missed the
   flattened `hp` key, so a `commandable: false` piece with a defense (the Recon Drone) composed as
   bodiless and was never given a component its scene lacked. Accepted by the deep layout dump
   (exactly the moved properties and the new nodes), the emission trace (byte-identical) and the
   flight traces.
5. The node is renamed from `Movement` to `Locomotion` through the importer. **Built
   2026-09-26**: `SpecComposition.RENAMED_COMPONENTS` renames it in place (see
   [entity-scene-hierarchy](entity-scene-hierarchy.md)); the seven hand-authored scenes no doc
   governs were renamed by the same header edit. Every piece's Locomotion node is now found by one
   name whatever its strategy, and `movement` is that node when it is navigated. Accepted by the
   deep layout dump: identical but for the node's name.

### Commandability is a capability, not a tier

The extraction site occupies the terrain grid and is therefore a fixture in every sense the grid
cares about — and it refuses to inherit `abstract_structure`, because nothing about it
responds to an order. Today that refusal is the only way to say so, which is why it is one
of the three hand-rolled outliers and why "structure" and "commandable" are welded together.

Under composition they come apart: **a command queue, `Selectable`, and the command routing
in `Commandable._process_commands` are a component set like any other, and a doc says
whether the piece gets them.** That is what lets the extraction site, `shelter` and `scout`
stop being hand-rolled scenes and become ordinary docs — §Step 4 already claims exactly
that for the three outliers, and this is the key that makes the claim literally true rather
than aspirational, because "everything my base would give me, minus the command queue" is
precisely what each of them was refusing.

**Declared, not derived.** No other key implies it: a footprint says nothing about whether
the player may select and order the thing, and both answers exist in today's roster on
pieces with identical component sets. So it earns a key of its own, on the same argument
that gives `repairs:` and `stealth:` bare bools — presence IS the capability.
**Recommendation: `commandable: false` as an explicit opt-out, defaulting true**, since the
overwhelming majority are commandable and map furniture is the exception that should have to
say so.

Two interactions to carry forward: `Commandable` stops being a class in the inheritance
chain and becomes a component set (a step 4 concern, not before), and §Blast radius gains
the `Commandable.is_built` and `can_rally` sites, which today assume every structure is
commandable.

---

## Migration order

Five steps. Each leaves the game playable and each has something verifiable at its end; the
order is chosen so that no step depends on a step after it.

### Step 0 — make component REMOVAL trustworthy

*No behaviour change. Nothing else in this plan is safe until this is true.*

The importer today overwhelmingly **adds**. Once the doc is authoritative, deleting a key must
delete a node, every run, without residue.

- Every component the importer can create, it can also remove.
- `TscnDoc.remove_node`'s orphaned-`ext_resource` pruning — added during the id-rename pass,
  after eight scenes were found pointing at a script that no longer existed and erroring on
  every load — **survives and becomes load-bearing.** It is currently a bug fix on a path that
  is rarely taken; under this plan removal is routine, so the pruning rule stops being a
  safety net and becomes part of the contract. It should gain a test of its own rather than
  remaining a comment on a helper.
- Removal must be **idempotent and total**: add → remove → add produces byte-identical output.

**Verifiable:** a round-trip test per component; a full import over the unchanged roster is a
byte-level no-op; no scene in the tree references a script that does not exist.

#### Built — 2026-08-28

Step 0 is done, with one acceptance criterion left unverifiable for a reason outside it.

**Removal is total.** `TscnDoc.remove_node` now takes the node, its descendants, and every
`ext_resource` **and `sub_resource`** the removal orphaned — reachability computed
transitively, so a mesh that names a material takes the material with it and a shape two
nodes share survives. Sub-resources used to be left alone deliberately ("they cost nothing
but a few unread lines"), which was true while removal was a rarely-taken bug-fix path and
false the moment it became routine: **every doc-governed shape is a sub-resource**, so
leaving one behind is the common case of residue, not the rare one. The `[ext_resource]`
block's blank-line shape is restored on removal too, which is the difference between
"add then remove" giving the bytes back and closing a gap it did not open.

**Every component the importer can create, it can now also remove.** Four collection keys
had no off-switch in the schema at all — `trains`, `builds`, `weapons`, `status_effects` —
so `false` becomes theirs, which is the spelling `repairs:` / `garrison:` / `stealth:`
already used. Two radius keys documented an off-switch the validator then rejected
(`beacon_range: false`) or silently mis-implemented (`detection: 0` wrote a zero-radius
cylinder instead of removing the volume); both now do what the schema always said. `true` is
refused on all of them, for the reason `garrison: true` is. The union type dies in
`SpecRegistry._normalize_removals`, so every consumer downstream still sees an Array.

Removal itself is now ONE function, `SpecSceneSync._remove_component`, rather than three
near-copies — which is what makes the round-trip identity a property of a function instead
of a habit.

**Tests.** `tests/test_TscnDoc.gd` carries the contract: add-then-remove restores the
original bytes and add → remove → add is byte-identical, parameterised over the three shapes
the importer creates (a script-only `Node`, a `Node3D` component, and a `CollisionShape3D`
that brings its own sub-resource); orphan pruning is covered for both resource kinds
including the transitive and the shared cases; and two sweeps run over the real roster —
every entity scene references a resource that exists, and removing each scene's own
root-level nodes one at a time leaves a document that still round-trips and names no
resource it no longer defines. The importer's validation covers the new off-switches and
the refusals.

**Verified 2026-09-25: a full import over the unchanged roster is a byte-level no-op.** Scene
paths are unique the way ids are: two docs naming one scene is a validation error, since each
would rewrite it on every run.

**Still open at the seam with step 4:** a weapon's `AttackRange` shapes are RESIZED and never
removed, because a melee weapon is spelled as a short reach rather than an absent one — so
there is no "no reach" state for removal to answer. That is correct today and worth
re-asking when the emission rework changes what a weapon's reach means.

### Step 1 — the activation axis

A two-form piece — `Structure` and `Movement` both present — has exactly one live: see
`Entity.deploy` / `undeploy` / `set_deployed`, `Movement.set_active`, and
`tests/test_TwoFormPiece.gd`. Two choices the code shows but does not argue:

- **Inactive reads as absent by default.** `Entity.movement` is null while the component is
  dormant, and `structure_is_active()` reads the flag, so the ~110 `movement` gates and the
  fixture checks needed no per-site verdict. Only what needs the dormant component (the
  switch, wiring that must survive it, footprint dimensions on a preview) reads the node.
  Changing only the sites this plan once listed would have left every other one treating a
  deployed piece as mobile.
- **The groups follow the form.** The switch moves the piece between `"unit"` and
  `"structure"`, so every group reader — movement routing, `is_built`, rally — follows it
  untouched.

PLANNED: nothing issues `deploy` / `undeploy` yet — the Deploy COMMAND is a different mechanic,
a unit planting itself without leaving its form ([deploying](../commands/deploying.md)). The transform ability (§The transformer —
an ability that calls them, keeping HP, veterancy and orders) and `build.completes_as`
(step 3's schema) are unbuilt, and no shipped piece has two forms.

A two-form piece contributes its infrastructure in both forms: contribution follows the
piece's `infrastructure` value, never whether it is standing as a structure
([production-and-economy](../macroeconomics/production-and-economy.md) §Infrastructure).

### Step 2 — the emission phase model

Built 2026-09-19 — [projectiles](../combat/projectiles.md) §Phases. The acceptance harness is
`tools/emission_trace.tscn`: every authored emission's damage per target per tick came through
unchanged. Four lifespans were rounded to clean seconds, so those flights end one tick earlier,
and `projectile.tscn` — a base, so it carries no phases — can no longer itself be fired; nothing
fires it.

The impact-shape answer was option 2 — presence of an authored value switched the behaviour,
through the `HitShape`'s `disabled` property — as a workaround for inherited nodes; step 5
retired it.

### Step 3 — narrow `kind:` to the class it loads

Built 2026-09-19. `kind:` names the class a spec loads as (`SpecRegistry.KIND_FAMILIES`), the
old categories are refused with their replacement named, and a lowercase class name gets the
casing rule explained. A piece's role — fixture or figure, built or trained — is derived from
`footprint:` and `movement:` (`SpecSchema.is_fixture`, `SpecGenerators._is_built`), a piece
with neither nor `senses.vision:` is refused, and a new skeleton inherits the mobile base when
the doc names `movement:`, gaining a `Structure` there if it also names a footprint. Validation
was already selected by the keys a doc declares; only the family switch remains, and it follows
the class.

Its acceptance held: the roster imported with every `kind:` rewritten and no doc, scene or
generated file changing except the nine scenes the empty-list rule empties (below), and the
reorder pass over the ordered roster is a byte-level no-op. Also built here, from the answer on
§Step 0: an **empty collection removes its component** and `false` is refused for those four
keys — eight Marxist and Theocratic structures lost a `Production` that trained nothing, and the
Technocratic builder a `Builds` that built nothing.

An ability doc is `kind: AbilityDefinition`, the class `AbilityCatalog` builds its entries as.

### Step 4 — compose the piece scenes

*The ~100-scene step, and the reason everything else comes first.*

- Component library (decided 2026-09-19): a SCRIPT NODE for a leaf component, a scene under
  `scenes/components/` for one with children or shapes of its own — the placement-and-art side
  of the doc/scene seam.
- `unit.tscn`, `abstract_structure.tscn` and `projectile.tscn` stop being inherited.
- Groups are written per piece from the derivation — **built 2026-09-19**, ahead of the rest:
  every piece root carries `SpecSchema.derived_groups` (`"piece"`, plus `"unit"` for a mobile
  piece that takes orders, `"structure"` for a fixture), which duplicates what the bases supply
  today and changed no resolved scene. The Recon Drone opted out of `"unit"` with
  `commandable: false`, which is what its doc already said.
- The shared locomotion core (§Locomotion is bigger than `Movement`) is extracted here.
- **The universal tier stops being universal.** `NavigationAgent`, `AvoidanceObstacle`,
  `MovementBody` and `AltitudeIndicator` are created for pieces whose composition needs them,
  so a structure stops carrying nav machinery it cannot use and `abstract_structure.tscn`
  stops having to override `MovementBody`'s shape because it cannot delete the node.
- **The three hand-rolled outliers stop being outliers.** The extraction site, `shelter` and
  `scout` hand-roll `Ownership` / `Structure` / `FootprintVisualizer` on a bare body precisely
  because they could not accept everything their base would have given them. After
  composition there is nothing to refuse: each becomes an ordinary doc naming a shorter
  component list. This step should **start** with those three, not end with them — they are the
  smallest scenes and they are the ones the old model could not express, so they are the
  honest proof that the new one can.

**Built 2026-09-25: the piece scenes are composed.** `commandable.tscn`, `unit.tscn` and
`abstract_structure.tscn` are deleted, and no entity scene inherits another — the 15 emissions
that inherited `projectile.tscn` and the one that inherited `irregular_bullet.tscn` included.
- The component library is 12 scenes under `scenes/components/`, extracted from the old bases so
  their defaults are byte-for-byte what the bases supplied.
- `tools/spec_import/composition.gd` derives a piece's root class and guaranteed components
  from its doc (see [entity-scene-hierarchy](entity-scene-hierarchy.md)). The importer writes a
  new piece as a bare root and `_sync_composition` adds the rest, which is also how an existing
  scene gains a component its doc now implies. A bodiless piece is composable: the old
  "author its scene by hand" error is gone.
- The universal tier stopped being universal: a structure has no `NavigationAgent`,
  `MovementBody`, `AvoidanceObstacle` or `AltitudeIndicator`. The runtime used to mirror the
  `MovementBody` shape onto the `TargetShape`, so the three structures whose `MovementBody` was
  a box (`cl_defense_antiAircraft`, `nt_extractor`, `facility`) now author that box on the
  `TargetShape` directly.
- The three outliers are ordinary docs: the extraction site and shelter say
  `commandable: false`, which makes them features on an `Entity` root; the Recon Drone keeps a
  `Commandable` root because it can be damaged.
- `SpecSceneSync.INHERITANCE_BASES` is gone (a step 5 item, done here because nothing is left
  to protect), so the generic `projectile.tscn` now gets its phases and can be fired.

**Accepted by the instantiated-layout diff** (`tools/scene_layout_dump.tscn`, with the new
`deep` mode recording every stored property): the composed scenes resolved identically across
4,213 nodes, except `cl_commandCenter`, which declared three `PlaceholderModel` siblings and now
has one. The trim then removed exactly the locomotion nodes and changed exactly the three
target shapes. A full import is a no-op on the result.

Found on the way: `TscnDoc` replaced only the FIRST line of a multi-line property value, which
Godot writes for an `Array[Dictionary]` or a string with newlines. It now edits whole value
spans (`TscnDoc._prop_span`).

**Still to do in step 4:**
- The shared locomotion core (§Locomotion is bigger than `Movement` §Order) is built, its own
  step 4 (`Aerial` / `Docking`) included; the Recon Drone keeps a speed-0 `Movement` by decision.
- TODO: `Commandable` as a component set rather than a class (§Commandability is a capability) —
  not started; today the root class is derived (Actor or feature) instead.
- `Emitter.launch` is the one call for an emission, and an emitted UNIT is built (2026-09-29):
  it is handed an order — attack the Entity it was launched at, or attack-move to the point —
  instead of a flight (`tests/test_EmittedUnit.gd`). TODO: only an ability's `emits:` may name
  a unit; the importer still requires a weapon's to be a projectile, and no piece emits one.
- The `"structure"` group is split (2026-09-29): `"fixture"` for every fixture, `"structure"`
  only for one that takes orders ([piece-vocabulary](piece-vocabulary.md) §Where today's code
  disagrees). PLANNED there, still: the `Commandable` → `Actor` and `Structure` → fixture
  component class renames.
- TODO: re-derive the [get-node-or-null-audit](get-node-or-null-audit.md) verdicts against the
  composed tiers.

**Built 2026-09-19: no piece has a root script of its own.** The four that did were folded into
components on a derived root, the way the shelter already was: `ExtractionSite`, `Extractor`
and `Beacon` are component nodes found with `X.of(piece)`, and the Recon Drone's empty `Scout`
subclass is gone (its root is `Commandable`). A `Beacon` signals `spent` as its host is freed,
so no piece overrides `Entity.expire` any more.

**Identity components are declared by PRESENCE only** (decided 2026-09-19): `shelter: true`,
`extraction_site: true`, `extractor: true` create or remove the component, and its tuning stays
scene-authored. The rule behind it: a mechanic earns a doc schema only once it is reused in
several places — a one-off would otherwise grow an importer transformer for one piece.
`Beacon` has no doc, so it stays scene-side until it has one.

### Step 5 — retire the inheritance workarounds

**Built 2026-09-26.** Everything that existed only because an inherited node could not be
removed is gone:

- A hitscan emission has no `HitShape`; its presence is the blast (`Payload.has_blast`), so
  neither the `disabled` flag nor `hitscan`'s authority over the shape is read any more.
- An emptied `senses.vision` removes the `VisionRange` node, and the `has_mesh_visual` waiver
  removes the `MeshVisual`; composition leaves both out of a piece that switched them off.
- No scene hides a stand-in `Model` beside real art, and the report tells a stand-in by what it
  instances (the shared structure dummy) rather than by where an inherited one used to sit —
  which also stops it counting a unit's own `Model` art as a stand-in.

Done early, with step 4: the importer's ban on adding a node to a base scene
(`SpecSceneSync.INHERITANCE_BASES`) and the "hide, never re-instance" convention in CLAUDE.md.

Accepted by the deep layout dump: exactly the nine hitscan emissions lost their `HitShape` and
nothing else moved; the emission trace is byte-identical.

---

## The four cases, traced

### The transformer (Sputnik)

*A piece that occupies the grid, then converts into something that moves.*

Doc declares both `footprint:` and `movement:`. Which one is live at spawn is the SITE's
answer, not the doc's (§Which form a piece spawns in). **Step 3** makes that combination
legal instead of a hard error. **Step 4** composes a scene with both components. **Step 1**
is what makes it correct at runtime: exactly one active, and switching gives back the grid
cells and navmesh hole or the nav agent. The transform itself is an ability that flips the
switch — no new spawn, no id change, no loss of the piece's HP, veterancy or orders.

The precedent for a per-tick re-file already exists: `Entity.refresh_targetable_altitude()`
re-files a piece's targetable layer on the tick its answer flips. Grid membership is the same
shape of problem, at a much lower rate.

### The bodiless entity (fog pseudo-unit)

*Owned by a commander, has vision and a lifespan, no model, not a combat target.*

Doc declares `vision:` and a lifespan and nothing else. **Step 3** derives "bodiless entity"
from the absence of `footprint:` and `movement:`. **Step 4** composes `Ownership` +
`VisionRange` + a lifespan and stops — no `MeshVisual`, no `Selectable`, no `Defense`, no
`HPBar`. Today the only way to get that is to refuse to inherit anything, which is what
`scout.tscn` does; note that today's Scout is deliberately a real 50-HP target, so the
pseudo-unit is a *second* variant that the current model would need a second hand-rolled scene
for and the new one gets from one doc.

### The emitted unit (Brood Lord)

*A weapon whose emission is a commandable unit.*

Nothing stops it once the **emitter interface** exists (step 4's companion): instantiate,
initialise against the owner, hand it its initial intent. The weapon names a piece id in
`emits:`; the emitter routes on what that id resolves to — a phase-moved token gets its phase list, a
`Commandable` gets a command. The emission class never learns that units exist, which is the
property worth protecting.

**What an emitted unit costs, and what it outlives** (decided 2026-09-28):

- **An emission costs nothing.** If one ever should, the price goes on the ABILITY that emits
  it — charges are paid for — never on the emitted piece itself.
- **There is no population to count it against** — the game has no population mechanic
  ([resources](../../setting/resources.md)).
- **An emission's lifespan is independent of its emitter.** It is not freed, recalled or
  orphaned-out when the piece that launched it dies.

### The continuous beam (Sonic Emitter)

*Damages everything it passes through, and never impacts.* Built at step 2: one moving phase
that does not end on arrival, pays out on a cadence and expires. The poison trail is the same
feature from the other side — a phase whose `emits:` drops a cloud every second. See
[projectiles](../combat/projectiles.md) §Phases.

---

## Where the doc/scene seam falls now

`tools/spec_import/README.md` draws the line today as **spatial vs not**: numbers and lists are
doc-governed, and anything positional — art, collision shape placement, node transforms — is
editor work.

Under this plan the line moves and changes shape. It becomes **composition and values are the
doc's; placement and art are the scene's**:

| Doc | Scene |
|---|---|
| which components exist | where a node sits |
| every scalar, enum and list they carry | which mesh, which material |
| a gameplay-meaningful size (a vision radius, a blast radius) | a shape's offset from the origin, a marker's position on a deck |
| groups, root class, folder | nothing |

The seam is wider than before — component existence crosses it, and that is the whole change —
but it does not swallow art. **One thing crosses in the other direction and should keep
crossing:** the generated-visual-defaults pass writes geometry no doc carries (a placeholder
mesh, a derived selection shape, an HP-bar transform). It stays exactly as it is, including
its "clearing a slot is the only rebake signal" rule, because it is derived from the ART
rather than from the doc and neither side of this seam is its owner.

---

## Blast radius

Classes of call site, not an inventory. Counts are the current tree.

| Class | Approx. sites | What happens |
|---|---|---|
| `is_in_group("unit")` / `is_in_group("structure")` | ~33 | **mechanism change**: groups come from base scenes today. They must be written per piece by the importer at step 4, before those bases go. |
| `get_node_or_null("<Component>")` @onready | ~141 | shape unchanged; the AUDIT's verdicts must be re-derived, since "optional" changes meaning |

---

## Risks, and what makes this survivable

- **It lands on a spec importer that is itself mid-change.** Steps 0 and 3 are importer work;
  steps 1 and 2 are not. Sequencing them apart is deliberate — do not start step 3 while the
  visual-defaults pass or the id conventions are still moving.
- **Step 4 is irreversible in practice.** Once a scene is composed rather than inherited,
  going back means rebuilding it. That is why step 4 comes last, why it runs in batches, and
  why the instantiated-layout diff is the acceptance test rather than a code review.
- **The three outliers are the canary.** If composition cannot express the extraction site,
  `shelter` and `scout` in one doc each, the model is wrong and it is far cheaper to learn that
  from three scenes than from a hundred.
- **Two vocabularies coexist for the length of the plan.** The four trajectory names survive
  as presets, and `kind:`'s game-design values (`unit`, `structure`, `projectile`) survive
  until step 3 rewrites them to class names. Both are deliberate; both should be deleted
  rather than left.
