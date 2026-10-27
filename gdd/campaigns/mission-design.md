# Mission design: lessons from prologue mission 1

Status: draft, written 2026-10-27 from the first built mission,
[prologue mission 1](01-prologue/01-pervasive-mechanics.md), by comparing its first design
(commit c81593be) with the mission as built (#39). These are the patterns the build settled on.
They apply to every campaign mission and challenge. A mission doc that departs from one says so
and why.

The systems behind each pattern are specified in
[scenario-scripting](../systems/scenario-scripting/README.md). This note covers *when to use*
them, not how they work.

## Shape of a mission

- **Start with almost nothing, and grow the force through the story.** The first design started
  with a few Irregulars and added a unit type per rescued cell. The built mission starts with one
  Warlord and grows by freeing captives. The first notes (selecting, moving, the camera) then
  have one unit to act on, and every new unit arrives with a reason.
- **A guide leads the early beats.** The ally's rescued squad walks ahead to each beat and waits
  there, holding fire, so the next goal is legible without arrows. Each change in its behaviour
  is a `TacticRule` reading the beat's trigger (`ConditionTriggerFired`), with the latest beat
  listed first. When the guide dies (the Clipper strike), that is a dramatic beat in itself, and
  it hands the player the lesson of the next objective.
- **Objectives read beats; they don't drive them.** The beats are triggers in the world. The
  objectives are one strict `ObjectiveChain` that only observes them, so a beat the player
  finished early is ticked off the moment its objective is shown. Navigating to several places
  is one objective with sub-steps. `resolves_earlier` is opt-in, and only for a beat a player
  could otherwise get stuck behind.
- **Optional content stays off the critical path, but it still counts in any tuned total.** The
  two optional prisons shift the defection threshold, from about 30% to 25%, or 3 of 16
  Compounds if the west prison falls too. Any ledger (infrastructure, unit counts, waves) is
  worked out with and without each optional piece.
- **The mission grows while it is built.** The first design had 5 objectives. The built mission
  has 9, plus prisons, transports, a relief force and about a dozen help notes. That growth is
  normal. What it costs is that mission 1 now covers ground the later missions had claimed
  (§Re-check the campaign after every build).

## Teaching

- **A note arrives just before the player needs it.** A help note is raised when the previous
  objective completes, and teaches what the next one needs (killing the outpost brings
  *Taking cover*). Notes come from the game-wide How to Play library. A note only one mission
  needs lives in `scenes/dialogs/<mission>/`. Each note covers one topic, and a trigger that
  teaches two things raises two notes.
- **A warning is a note raised on first sight.** The Watch Tower warning fires the first time a
  tower is visible to the player (`ConditionGroupVisible`). Use this for any threat the player
  should avoid until later in the mission.
- **Teach a system once, not each of its instances.** The sanction system is taught once; the
  player learns later ordnances and abilities from their tooltips (Alex, 2026-10-27).
- **The Teaches list matches what is actually taught.** Each item maps to a note or a beat. When
  a lesson is dropped (stop, in mission 1), take it off the list.
- **A constraint is re-checked against the built scene.** "No mechanic before it is explained"
  only holds if every placed and spawned piece is checked against it, the ally's included.

## Information

- **Marks are hidden by the fog, and reveals are chosen per objective.** An objective's targets
  are marked only where the player could see them. When the player should know where to go, a
  standing reveal shows it while the objective is current. An objective about *finding*
  something gets no mark and no reveal.
- **What the ally can see is something to unlock.** The ally keeps its vision from the player
  until a beat, so the player's own sight matters early. Sharing it later is a reward.
- **A fight the player can't see yet gets a labelled reveal**, and it is ended by name when the
  story moves on, not on a timer.

## Opponents

- **Mission bots are scripted only.** Every bot job that acts is switched off
  (`PlayerSlot.disabled_bot_jobs`). PASSIVE is not enough, because a passive brain still
  defends its base and wrecked the rescue.
- **Anything present from the first frame is placed in the scene, not spawned.** Its author can
  then put it exactly where it stands. A group waits for its beat under a first rule that holds
  its post and holds fire.
- **A defending group shares one defended area** (`DefendedArea`). Otherwise the player picks
  its units off one by one from just outside each one's aggro range.
- **Reinforcements spawn relative to whatever they attack** (`follow_group`, from off the map,
  flown in), out of the player's reach, so they arrive where the story needs them wherever the
  player went.
- **Waves follow the player's approach, not a clock.** A side's next wave is set off when the
  other side approaches, and never while its previous wave lives. Repeating timers wore the
  lane down. Waves stop when the beat that should stop them happens (defection, in mission 1).
- **A failure condition names what the mission depends on**, not only a total wipe ("at least
  one Warlord"). A unit sheltering or carried counts as alive.

## Saves

- **Autosave on milestones only.** Mission 1 has three, each just after a beat that would hurt
  to replay. Choose them per mission.

## Building the map

- **Settle the topology before sculpting it.** Grey-boxing and proposal rounds stalled until
  Alex drew the topology. A drawing imported once through the map generator's image mode gave a
  playable map in one step.
- **One primary per artifact, recorded in the mission doc.** Once imported, the terrain and
  the scene are primary and edited by hand. A tool that lays them down refuses to overwrite.
  Rescaling or re-importing maps every piece and trigger through the same mapping.
- **Probe each beat headlessly after a change.** The useful checks were walk times, who wins an
  unattended fight, and whether each trigger fires in the intended order.

## Re-check the campaign after every build

When a mission's build is settled, re-read the campaign README and every later mission doc
against it:

- What it now teaches, which a later mission's Teaches may claim
- What it shows (pieces and mechanics, the ally's included), which the campaign may defer
- Where its story ends, which a later mission's hook may contradict
- What it established (notes in the library, scripting features), which a later mission can
  reuse

Mission 1's results: see [the prologue README](01-prologue/README.md) §Impact of mission 1's
build.
