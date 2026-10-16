---
title: Netplay
type: system-note
---

# Netplay

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

Scoped 2026-10-12. **Built: the widened digest, the input buffer, the wire format and the
transport interface with a loopback for tests (2026-10-13); the lockstep loop, the ENet transport,
the handshake and the ready barrier, the Multiplayer lobby, the per-player verdict, and desync
detection (2026-10-14). A networked skirmish can be hosted, joined and played, and two processes
on one machine play it in step (`test_TwoProcessNetplay`). Two machines over Wi-Fi — a Mac
hosting, a Windows PC joining — played 900 ticks in step on 2026-10-14 (`tests/_netplay_peer`
with `--address`).** Players on different machines play one match by sending each other their
orders, and every machine runs the whole simulation. The direction is Alex's (2026-10-11): **deterministic lockstep now, rollback in the long term**, and lockstep is
built in rollback's shape so the step from one to the other adds to it rather than replacing it.
The first build's decisions were made 2026-10-13 ([`gdd/tasks.md`](../../tasks.md) T-107) and
are under §Decisions.

## The model

Built, except where marked. **The simulation only ever consumes "every commander's orders for tick N".** A turn is
one commander's `PlayerOrder`s for one tick ([recording-and-replay](recording-and-replay.md)
§The order stream). It is sent for every tick, and an empty turn is sent explicitly, because "this
player gave no orders on tick N" has to be confirmed, not assumed.

- **An order is sealed into the turn for the tick it will apply on**: the tick it was given plus
  the input delay (`Lockstep.seal`). Live single-player, replay and netplay keep one rule: an
  order applies at the start of its tick. Alone, at a delay of zero, the loop is the
  single-machine stream exactly.
- **Confirmed** means every peer's turn for that tick has arrived. Lockstep runs a tick only once
  it is confirmed. Until then `OrderStream` holds the world (`REASON_NETWORK_WAIT`), taken and
  released at the start of a frame, so a tick runs whole or not at all.
- **Every peer applies the decoded form of every turn**, its own included: a local turn is sealed
  through the same JSON round trip a remote one arrives through.
- **Rollback is lockstep with a run-ahead window.** A client runs up to W ticks past the newest
  confirmed one, standing in an **empty turn** for each missing remote turn. A turn that then
  arrives with orders in it means re-running from the newest snapshot before it. This is
  ShieldBattery's model (§Reference). **Lockstep is the same machine with W = 0**
  (`Lockstep.RUN_AHEAD_TICKS`, a constant until rollback can correct a guessed tick), and nothing
  is written as a hard-coded lockstep gate.
- **Bots are not networked.** Every peer runs every bot from the match seed, as a replay already
  does. A remote human's commander is a `Bot` with its brain off, as a playback's human slot is:
  `Scenario.local_commander_id`, set before the scenario enters the tree, names this machine's
  seat; it alone gets the player's rig, and every other human slot's orders arrive over the
  network (`test_RemoteHumanSlot`).
- **Topology stays out of the simulation.** Everything that knows about peers sits behind one
  transport interface. Peer-to-peer comes first; a relay or client-server design is a second
  implementation of the same interface, not a change to the simulation.

## What lockstep builds that rollback keeps

Each item is built once, for lockstep, and survives unchanged. Built items name their code; the
rest are PLANNED.

- **The transport interface**: `NetTransport` (`scripts/netplay/`), datagram semantics — a message
  may be lost, delayed, duplicated or reordered, and nothing above relies on otherwise. Built with
  `LoopbackNetwork`/`LoopbackTransport` for tests: latency, loss and duplication on a stepped
  clock, from the network's own seeded stream. Built 2026-10-14: `ENetTransport`, peer-to-peer by
  address and port in a full mesh. In each pair the higher id dials the lower and names itself in
  ENet's connect data, so a connection is identified as it opens and a machine needs only the
  addresses below it; a dropped dial is dialled again. Sends are unsequenced and unreliable.
  `test_ENetTransport` runs it over real sockets on this machine, two lockstep sessions included.
- **The input buffer**: `InputBuffer` holds `Turn`s by (tick, commander) and the newest contiguous
  tick per commander; a tick is confirmed once every commander's turn has arrived. A resent copy
  of a held turn is accepted; a turn that contradicts one is refused. `orders_for(tick)` gives one
  order for every peer — by commander id, then as given — so arrival order never matters. It is
  the core data structure of every rollback library, and it is ours. A commander that forfeits is
  FENCED at an agreed tick (`InputBuffer.fence`): from it on the buffer stands in its turns — a
  FORFEIT order on the fence tick, empty after — and ignores any it sends.
- **The wire format**: `TurnPacket` — the sender's unacknowledged turns plus its acknowledgement
  of the receiver's, JSON in the replay file's `PlayerOrder.to_dict` encoding, with a wire
  version refused on mismatch. Every packet repeats every unacknowledged turn, so a lost packet
  costs only the wait for the next. `test_LoopbackTransport` runs two peers over a lossy,
  reordering link to the same confirmed ticks and orders.
- **The loop**: `Lockstep` seals the local turn, pumps packets, and says whether a tick may run;
  `OrderStream.join_lockstep` drives it once a frame. Tested over the loopback with two and three
  peers on lossy, slow, reordering links (`test_Lockstep`), and in a real match held through
  repeated stalls that plays back digest for digest (`test_ReplayRoundTrip`).
- **The input delay**, as a setting: `Lockstep` takes it in seconds and holds it in ticks.
  Rollback keeps one; it only gets smaller.
- **Session setup**: built 2026-10-14. `NetSession` — every peer sends every other its whole status
  each frame, unacknowledged, a lost one replaced by the next: its build (the replay version
  stamp), whether it has loaded the map and what that map hashed to (`MapDigest`), and
  whether it has started. The host's status carries the match: the recipe
  (`SkirmishSetup.recipe`), each peer's seat (the commander it plays) and the input delay, kept in
  wire form so the host builds from what every peer builds from. A different build, a different
  map or a peer with no seat refuses the match, with a reason. The session and the turns
  share one connection on two channels (`TransportMux`), each reading only its own messages.
  `NetMatch`, a node in the scenario, holds the world until the session is ready, then starts the
  `Lockstep` and joins it to the stream; orders given while held go out in the first turn.
  `test_NetSession`, `test_TransportMux`, `test_NetMatch`.
- **Desync detection**: built 2026-10-14. `DesyncCheck` — every peer digests the start of each
  simulated second (`SimulationDigest`, widened per §Decisions) and sends the others its last few,
  repeated in every packet on their own channel (`TransportMux.DIGESTS`); the first tick whose
  digests differ is the desync. A peer that sent two different turns for one tick
  (`Lockstep.contradiction_tick`) is one too. `NetMatch` then holds the world for good, writes
  this machine's state string for that tick to `user://desync/`, and ends the match with a
  desync notice. `test_DesyncCheck`, `test_NetMatch`.
- **Disconnect handling**, and the waiting-for-player readout: built 2026-10-14 (§Decisions, a
  silent peer).
- **Feedback for orders not yet applied.** Under input delay an order shows before it applies.
  Built 2026-10-14 (§Decisions, order feedback).

## Rules

Built where it names code; PLANNED otherwise.

- **A hold changes nothing but timing.** Peers stall at different moments for different lengths,
  so a match held for any number of frames must play exactly as one never held. Built
  2026-10-14: [scenario-scripting/dialogs-and-pause](../scenario-scripting/dialogs-and-pause.md)
  §A hold changes nothing but timing — engine frame counters, navigation agents and the
  navigation server each broke it.

- **Tick 0 runs only once every peer reports its map and scenario loaded.** Map generation takes
  10–25 s and differs per machine ([ux/ui/menus](../ux/ui/menus.md) §Generation runs off the main
  thread). Built: `NetMatch` is added to the scenario before it enters the tree and holds the world
  from its first frame. Loaded means in the tree with its map built; the opening force waits on
  `NavManager.navmesh_ready`, which fires from a physics frame, so it lands on the same tick after
  the release on every machine — a match started this way plays back exactly (`test_NetMatch`).
- **Debug mode, playback speed and pause are refused in a networked session.** Each changes the
  simulation or its rate on one machine only. Built: `SimulationClock` takes no hold but the
  network wait in a networked scenario (`Scenario.is_networked`), so the pause menu and the help
  book are overlays that hold nothing; debug mode — which carries playback speed — is never
  permitted (`Scenario.is_debug_permitted`). `test_NetworkedHolds`.
- **No interface side effect fires from inside the apply path.** A waypoint, a bark or a selection
  change must not assume an applied tick is final, or rollback will repeat it. Lockstep doesn't
  need this, and retrofitting it is the expensive part. Waypoints are built so (§Decisions, order
  feedback). TODO: a DROP still selects its landed pieces, and a toggle refreshes the card, from
  `RTSController._on_order_applied` — both want the same treatment before rollback.
- **Nothing in a networked match's simulation reads the local player.** Each peer has a
  different one. Built 2026-10-14: HEGEMONY's verdict is judged for every commander alike, and the
  local player is only told theirs
  ([scenario-scripting/objectives-and-completion](../scenario-scripting/objectives-and-completion.md)
  §Win conditions). The remaining reads of `RTSController.PLAYER_COMMANDER_ID` are presentation
  (stealth's HP-bar hiding, status visuals, fog display, beacon tint, the summary's title), or
  MISSION's implicit loss and an authored verdict, which only single-player sessions have.
- **A replay of a networked match records every human's orders** from the confirmed stream, and
  its header names the seat it was recorded from (`local_commander_id`), which its playback
  plays from: the simulation still reads the local player (the verdict, the implicit loss).
  Built.

## Decisions

Decided 2026-10-13 (T-107). PLANNED, except where a decision names the code that builds it.

- **Turns:** one per tick (30 a second). An empty turn is sent explicitly.
- **Input delay:** fixed for the match, set from the round trip measured in the lobby; the host
  can edit it. Built: the slowest round trip to the host plus a tick (`LobbyLink.measured_delay_seconds`).
  TODO: joiners' round trips to each other are not measured.
- **Order feedback:** shown at submit, previewed through the dispatcher's own rules
  (`recipients`, `line_destinations`). Nothing fires at apply. Built 2026-10-14:
  - At submit the controller previews each recipient's destination — `recipients`, then
    `line_destinations` or `fanned_destinations` — and draws it until the order applies
    (`RTSController._order_previews`), matched back by content, since a networked match applies the
    copy decoded off the wire.
  - Once applied, a waypoint is read off the units' own commands each frame: the dispatcher marks
    the messages a player's order placed (`CommandMessage.shows_waypoint`), identically on every
    machine. The old registry, filled from the apply, is gone.
  - Only the local player's own units are drawn: selecting a rival's must not show where it was
    sent. `test_OrderFeedback`.
- **Transport:** direct ENet by address and port. TODO: NAT traversal and a relay, behind the
  transport interface.
- **Peers:** N in a full mesh, tested at 1v1 and 2v2.
- **A silent peer:** a timeout with a waiting-for-player readout, then that player forfeits.
  TODO: a bot takes the slot at an agreed tick, for team games. Built 2026-10-14, at Alex's
  leanings: the timeout is 30 s, and forfeiting is losing every command centre — eliminated, its
  pieces freed (`Scenario.forfeit`, a FORFEIT `PlayerOrder`, so a replay plays it back).
  - `NetMatch` names who a stalled tick waits on from its first second ("Waiting for Player N…
    forfeits in X s"), and at 30 s VOTES that peer out (`Lockstep.vote_out`).
  - A peer that has voted ignores the silent peer's packets from then on, so its vote — how far it
    holds the silent peer's turns — never changes; every vote rides the turn packets and carries
    those turns, relayed so every voter holds the same.
  - Once every peer still playing has voted, each fences the silent peer one tick past the
    furthest any vote reached, so all apply the FORFEIT on the same tick, holding the same turns
    before it. In a 1v1 the one remaining peer fences at once.
  - TODO: "still playing" is each peer's own view, so a network split three ways can fence at
    different ticks; and a peer cut off rather than gone forfeits the others on its side — two
    matches each claiming the win. A relay or a server as judge would settle both.
  - `test_Lockstep` (three peers, lossy links, a peer that comes back after its fence),
    `test_NetMatch` (the readout, then the forfeit, in a real scenario).
- **Platforms:** any OS and CPU architecture may play together — the handshake refused another
  until Alex lifted that on 2026-10-15. Mixed platforms compute the same match because simulation
  maths goes through `DMath`, every basis the game turns is written with it, and digests round by
  arithmetic ([native-code](../authoring/native-code.md) §Maths that rounds the same everywhere).
  - Measured 2026-10-14, macOS/arm64 against Windows/x86_64, with `tools/netplay/determinism_probe`
    and `compare_determinism.py`: before, one bot match parted at tick 357 on the platforms' C
    maths libraries; after, a five-minute HARD bot match, Colonial against Anarchical, agreed to
    the bit for all 9000 ticks — every digest, and every piece's position and velocity.
  - TODO: one match is a sample. It never reached late tiers, turreted pieces or superweapons;
    more seeds, each faction on each side, and matches played to a verdict would cover them. A
    cross-platform drift in the meantime ends the match as any desync does, with both machines'
    state written out (§Decisions, on a desync).
- **The digest covers everything a physics tick governs**, not only positions, HP and resources:
  the RNG state, each actor's current command and queue, production and research progress,
  cooldowns, and any other per-tick simulation state. Still built once a second. Entities are
  keyed and sorted by `Entity.spawn_serial`, not the piece id, so the order does not lean on
  positions differing and a diff names the exact piece. Built 2026-10-13: `SimulationDigest`
  covers `SU.rng` and each bot brain's stream; per commander energy, dominion, the production
  queue's length, upgrades and elimination; per piece position, velocity, HP, the command chain,
  each weapon's cadence (`Weapon.digest_token`), production jobs, ability pools and status
  effects; and every other entity a commander holds, by position. The digest's script is in
  `ReplayFile.VERSIONED_PATHS`, so a replay recorded with another digest is refused rather than
  reported as drifting. TODO: Godot's global generator has no readable state and is not
  covered.
- **On a desync:** the match ends for everyone with a desync notice; each peer writes its
  `SimulationDigest.state_string` for diffing.
- **Sessions:** skirmish only. Missions stay single-player.
- **Pause:** none in a networked match (§Rules).
- **The verdict:** judged for every human slot inside the simulation; each viewer reads their
  own. The verdict becomes simulation state. Built: every commander's, under HEGEMONY
  (`Scenario.verdict_of`).
- **Entry:** a Multiplayer page with Host and Join (by address) into the existing
  `SkirmishLobby`. The host edits `SkirmishSetup`, joiners see it read-only and claim a slot, and
  the host broadcasts the recipe. Decided 2026-10-14: the host marks each slot Bot or Open and a
  joiner may take only an Open one; joining seats you in the first free Open slot at once (refused
  when none is free), and you may move; Play waits until every Open slot is taken. The host always
  plays slot 1, since a watching host would need observers. Built — [ux/ui/menus](../ux/ui/menus.md)
  §Multiplayer.
- **Chat:** none in the first build (TODO).
- **The map:** each peer generates from `map_seed`, and peers compare a map digest before tick 0.
  Built: `MapDigest` hashes the terrain (heights, tiles, void cells) and every piece placed with
  the map.
- **Testing:** a GUT test launches two headless processes on localhost over the real transport,
  shaped like `test_ReplayRoundTrip`. The input buffer, wire format and confirmation logic get
  pure tests with injected latency and loss. Built 2026-10-14: `test_TwoProcessNetplay` runs two
  peers (`tests/_netplay_peer.tscn`) through the whole path — lobby, Play, map generation,
  `NetMatch.build_scenario`, lockstep over ENet — each giving an order, and requires the same
  orders on the same ticks and the same digest every second, with no desync. About 20 s.

## Rollback, later

TODO, all of it: none of this is planned yet, and lockstep does not wait on it.

- **Tick cost is the gate, not the netcode.** Rolling back k ticks re-runs k ticks inside one
  frame. A tick cost 12–23 ms between minutes two and six, and 70–85 ms in a fought late game
  ([ai/bot-performance](../ai/bot-performance.md) §Re-measured 2026-10-10), against a 33 ms
  budget; a Brood War step costs about 0.3 ms. Rollback wants a tick roughly ten times cheaper,
  and that measurement comes before any snapshot design.
- **Snapshot and restore of the whole simulation**, shared with replay seeking
  ([recording-and-replay](recording-and-replay.md) §Deferred goals). It is a serialization, not a
  memory copy: Godot allocates nodes, navigation agents and physics bodies during play, and the
  navigation and physics servers hold state outside the tree. Snapshot primary state only; derived
  terrain, visual facets and presentation are rebuilt or left alone.
- **A state inventory**: every field classified as primary, derived or presentation. The digest
  widening above is its first draft.
- **Once per frame, not once per re-simulation**: sounds, alerts, effects and the order-feedback
  hooks are matched against what an earlier run of the same tick already did. Viewer-local state
  (camera, selection, the displayed fog) stays out of snapshots.
- **Update order by serial.** Built 2026-10-15: one stepper steps every entity in spawn-serial
  order. PLANNED: a decide phase and an act phase, and references between pieces held as
  serials — [the-simulation-step](the-simulation-step.md).
- **Bot state** goes into snapshots, since every peer's bots re-run on rollback.
- **The match end and a departure are fences**: applied only on a confirmed tick, and never
  rolled back across.
- **A forced-rollback replay harness**: a replay played with rollback forced on every tick must
  match plain playback digest for digest. It finds state a snapshot misses.
- **The library.** Alex's plan named Delta Rollback (C++ GDExtension) and Snopek's Godot rollback
  addon (GDScript). Both expect state to be saved and loaded per node, and Snopek's also expects to
  own the tick loop. Choose, or write our own on top of the input buffer above, once the tick-cost
  gate is met.

## Reference: ShieldBattery

[ShieldBattery](https://github.com/ShieldBattery/ShieldBattery) (MIT) is a Brood War launcher with
live rollback. [`docs/rollback.md`](https://github.com/ShieldBattery/ShieldBattery/blob/master/docs/rollback.md)
is the map, `game/src/rollback/` the engine, and `game/src/netcode_v2/input_table.rs` the input
table. **No code is reusable**: it is a Rust DLL that hooks the game's memory, and its snapshot is
a copy of fixed memory ranges, which works only because Brood War allocates nothing during play.
What carries over is the design:

- every step consumes exactly one turn per slot, so a turn index is a step index;
- missing turns are empty turns; a prediction limit (8) stalls past it, and a limit of 0 is
  lockstep;
- each player splits their own round trip between input delay and rollback, against a relay's
  session clock;
- state hashes every 8th confirmed step, compared by the relays, which evict a diverged minority;
- the replay records only confirmed turns;
- dynamic turn rates played worse than a well-chosen fixed rate (lockstep era).
