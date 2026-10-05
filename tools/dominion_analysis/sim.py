"""Step 2 of the dominion-rate analysis: one player, alone on an exported map, earning dominion
as fast as its faction's primary mechanic allows, under the game's real energy costs and income.

A one-second time step. What it models, faction by faction, and every simplification, is
written up in gdd/systems/macroeconomics/pacing/dominion-rate-analysis.md §The model. In short:

* The opening follows the real rules: starting units at the start point, the command centre and
  the two free extractors dropped there at t = 0 (the extractors pay a site's rate and draw
  infrastructure), the skirmish's starting energy granted on the drop.
* Costs are paid when a build or a training job STARTS, and a job that cannot be paid waits.
  Infrastructure works the same way: a piece that draws it needs the spare.
* Ground units walk shortest paths over the walkable grid; fliers go straight. Scouting is
  explicit: extraction sites and ponds are unknown until a unit's vision has covered them.
  Shelters are known from t = 0 (the HEGEMONY opening reveal).
* Each faction plays a small, explicit strategy with a few knobs (its POLICY). run.py tries
  every combination and keeps the best — a stand-in for a good player, not a bot.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np
from scipy.signal import fftconvolve

from mapdata import MapData

CHECKPOINTS = (180, 300, 600, 900)


@dataclass
class Unit:
    kind: str
    pos: tuple
    speed: float
    flying: bool
    vision: float
    task: dict | None = None
    uid: int = 0
    carry: float = 0.0


@dataclass
class Structure:
    kind: str
    pos: tuple
    done: bool = False
    queue: list = field(default_factory=list)  # [type, ...] waiting to start
    job: list | None = None  # [type, seconds left]
    state: dict = field(default_factory=dict)


class World:
    def __init__(self, facts: dict, m: MapData, faction: str, policy: dict, start: int = 0):
        self.f = facts
        self.p = facts["pieces"]
        self.m = m
        self.faction = faction
        self.policy = policy
        self.t = 0
        self.start = m.starts[start]
        self.energy = float(facts["start"]["energy"])
        self.dominion = 0.0
        self.infra_provided = 0
        self.infra_drawn = 0
        self.explored = np.zeros((m.d, m.w), dtype=bool)
        self.units: list[Unit] = []
        self.structures: list[Structure] = []
        self.incomes: list[dict] = []  # {"rate": e/s, "charge": remaining or None}
        self.site_state = [None] * len(m.sites)  # None | "reserved" | "extractor" | "lab"
        self.pond_state = [None] * len(m.ponds)
        sh = facts["shelter"]
        self.shelters = [
            {"pos": p, "residents": sh["capacity"], "timer": sh["spawn_interval"]}
            for p in m.shelters
        ]
        self.series: list[float] = []
        self.rate_series: list[float] = []
        self.log: list[str] = []
        self._uid = 0
        self._disks: dict[float, np.ndarray] = {}
        stride = facts["assumptions"]["explore_stride_cells"]
        self.lattice = [
            (x + 0.5, z + 0.5)
            for z in range(stride // 2, m.d, stride)
            for x in range(stride // 2, m.w, stride)
            if m.walkable[z, x]
        ]
        self._deploy()

    # --- bookkeeping --------------------------------------------------------------------------
    @property
    def infra_spare(self) -> int:
        return self.infra_provided - self.infra_drawn

    def _infra_change(self, kind: str, sign: int = 1) -> None:
        v = self.p[kind]["infrastructure"] * sign
        if v > 0:
            self.infra_provided += v
        else:
            self.infra_drawn += -v

    def can_pay(self, kind: str) -> bool:
        draw = max(0, -self.p[kind]["infrastructure"])
        # A piece that draws nothing is never held up by strain (the Relay a strained
        # Libertarian needs most of all).
        return self.energy >= self.p[kind]["energy"] and (draw == 0 or self.infra_spare >= draw)

    def has_tech(self, kind: str) -> bool:
        return all(any(s.kind == r and s.done for s in self.structures)
                   for r in self.p[kind]["requires"])

    def pay(self, kind: str) -> None:
        self.energy -= self.p[kind]["energy"]

    def add_unit(self, kind: str, pos) -> Unit:
        self._uid += 1
        pc = self.p[kind]
        u = Unit(kind, (pos[0], pos[1]), pc["speed"], pc["flying"], pc["vision"], uid=self._uid)
        self.units.append(u)
        self._infra_change(kind)
        return u

    def add_structure(self, kind: str, pos, done: bool = False) -> Structure:
        s = Structure(kind, (pos[0], pos[1]), done=done)
        self.structures.append(s)
        if done:
            self._infra_change(kind)
        return s

    def finish(self, s: Structure) -> None:
        s.done = True
        self._infra_change(s.kind)
        self.on_finished(s)

    def disk(self, r: float) -> np.ndarray:
        d = self._disks.get(r)
        if d is None:
            d = self._disks[r] = MapData.disk(r)
        return d

    def _deploy(self) -> None:
        sx, sz = self.start
        cc = self.f["start"]["command_centres"][self.faction]
        self.cc = self.add_structure(cc, self.start, done=True)
        for i in range(self.f["start"]["free_extractors"]):
            # Dropped beside the command centre; a free extractor gets its own site underneath.
            self.add_structure("nt_extractor", (sx + 7 * (1 if i == 0 else -1), sz + 6), done=True)
            self.incomes.append({"rate": self.f["rates"]["extractor_per_second"], "charge": None})
        for kind in self.f["start"]["units"][self.faction]:
            self.add_unit(kind, self.start)
        for s in self.structures:
            self.m.stamp(self.explored, s.pos, self.disk(self.p[s.kind]["vision"]))

    # --- what is known ------------------------------------------------------------------------
    def known(self, p) -> bool:
        x, z = self.m.cell_of(p)
        return bool(self.explored[z, x])

    def free_sites(self) -> list[int]:
        return [i for i, (p, _) in enumerate(self.m.sites)
                if self.site_state[i] is None and self.known(p)]

    def free_ponds(self) -> list[int]:
        return [i for i, pd in enumerate(self.m.ponds)
                if self.pond_state[i] is None and pd["charge"] > 0 and self.known(pd["center"])]

    def nearest(self, pos, points) -> int | None:
        best, best_d = None, math.inf
        for i, p in points:
            d = self.m.walk_distance(pos, p)
            if d < best_d:
                best, best_d = i, d
        return best

    # --- orders -------------------------------------------------------------------------------
    def order_build(self, u: Unit, kind: str, pos, on_done=None, tag=None) -> bool:
        if not (self.can_pay(kind) and self.has_tech(kind)):
            return False
        self.pay(kind)
        s = self.add_structure(kind, pos)
        s.state["tag"] = tag
        s.state["on_done"] = on_done
        if self.p[kind]["infrastructure"] < 0:
            self.infra_drawn += -self.p[kind]["infrastructure"]  # reserved from the order on
            s.state["infra_reserved"] = True
        u.task = {"type": "build", "target": pos, "structure": s,
                  "left": self.p[kind]["build_seconds"]}
        return True

    def order_move(self, u: Unit, target, then: str = "move", **extra) -> None:
        u.task = {"type": then, "target": target, **extra}

    def queue_train(self, s: Structure, kind: str) -> None:
        s.queue.append(kind)

    def queued(self, kind: str) -> int:
        n = 0
        for s in self.structures:
            n += s.queue.count(kind) + (1 if s.job and s.job[0] == kind else 0)
        return n

    def count(self, kind: str, done_only: bool = True) -> int:
        return sum(1 for s in self.structures if s.kind == kind and (s.done or not done_only)) + \
            sum(1 for u in self.units if u.kind == kind)

    # --- the tick -----------------------------------------------------------------------------
    def run(self, seconds: int = CHECKPOINTS[-1]) -> "World":
        for _ in range(seconds):
            self.decide()
            self._tick()
        return self

    def _tick(self) -> None:
        dt = 1.0
        self.t += 1
        # Income.
        for inc in self.incomes:
            if inc["charge"] is None:
                self.energy += inc["rate"] * dt
            elif inc["charge"] > 0:
                take = min(inc["rate"] * dt, inc["charge"])
                inc["charge"] -= take
                self.energy += take
        # Production.
        for s in self.structures:
            if not s.done:
                continue
            if s.job is None and s.queue:
                kind = s.queue[0]
                if self.can_pay(kind) and self.has_tech(kind):
                    s.queue.pop(0)
                    self.pay(kind)
                    s.job = [kind, self.p[kind]["build_seconds"]]
            if s.job is not None:
                s.job[1] -= dt
                if s.job[1] <= 0:
                    u = self.add_unit(s.job[0], s.pos)
                    s.job = None
                    self.on_trained(u, s)
        # Units.
        for u in list(self.units):
            moving = u.task is not None
            self._advance(u, dt)
            if u.vision > 0 and (moving or not u.__dict__.get("stamped")):
                self.m.stamp(self.explored, u.pos, self.disk(u.vision))
                u.__dict__["stamped"] = True
        # Shelters repopulate.
        sh = self.f["shelter"]
        for s in self.shelters:
            if s["residents"] < sh["capacity"]:
                s["timer"] -= dt
                if s["timer"] <= 0:
                    s["residents"] += 1
                    s["timer"] += sh["spawn_interval"]
        rate = self.dominion_rate()
        self.dominion += rate * dt
        self.rate_series.append(rate)
        self.series.append(self.dominion)

    def _advance(self, u: Unit, dt: float) -> None:
        task = u.task
        if task is None:
            return
        if task["type"] == "build":
            target = task["target"]
            standoff = self.f["assumptions"]["build_standoff_cells"]
            if math.dist(u.pos, target) > standoff + 0.75 and not task.get("arrived"):
                u.pos, left = self.m.step_toward(u.pos, target, self._budget(u, dt), u.flying)
                u.carry = min(left, 0.0)
                if left > 0 or math.dist(u.pos, target) <= standoff + 0.75:
                    task["arrived"] = True
                return
            task["arrived"] = True
            task["left"] -= dt
            if task["left"] <= 0:
                s = task["structure"]
                if s.state.get("infra_reserved"):
                    self.infra_drawn -= -self.p[s.kind]["infrastructure"]
                self.finish(s)
                u.task = None
                cb = s.state.get("on_done")
                if cb:
                    cb(s)
            return
        if task["type"] == "wait":
            task["left"] -= dt
            if task["left"] <= 0:
                u.task = None
            return
        # move / explore / any errand: travel, then hand arrival to the faction
        u.pos, left = self.m.step_toward(u.pos, task["target"], self._budget(u, dt), u.flying)
        u.carry = min(left, 0.0)
        if left > 0 or math.dist(u.pos, task["target"]) < 0.75:
            u.pos = task["target"]
            done = task
            u.task = None
            self.on_arrived(u, done)

    @staticmethod
    def _budget(u: Unit, dt: float) -> float:
        return u.speed * dt + u.carry

    # --- faction hooks (overridden) ----------------------------------------------------------
    def decide(self) -> None: ...

    def on_finished(self, s: Structure) -> None: ...

    def on_trained(self, u: Unit, s: Structure) -> None: ...

    def on_arrived(self, u: Unit, task: dict) -> None: ...

    def dominion_rate(self) -> float:
        return 0.0

    # --- shared behaviours --------------------------------------------------------------------
    def explore(self, u: Unit) -> None:
        """Send `u` to the nearest unexplored lattice point (straight-line nearest; it walks
        the shortest path there)."""
        best, best_d = None, math.inf
        for p in self.lattice:
            if self.known(p):
                continue
            d = (p[0] - u.pos[0]) ** 2 + (p[1] - u.pos[1]) ** 2
            if d < best_d:
                best, best_d = p, d
        if best is not None:
            self.order_move(u, best, then="explore")

    def build_extractor(self, u: Unit) -> bool:
        """Claim the nearest known free site or pond for an energy extractor."""
        options = [("s", i, self.m.sites[i][0]) for i in self.free_sites()]
        options += [("p", i, self.m.ponds[i]["center"]) for i in self.free_ponds()]
        if not options or not self.can_pay("nt_extractor"):
            return False
        j = self.nearest(u.pos, [(k, o[2]) for k, o in enumerate(options)])
        kind, i, pos = options[j]
        if kind == "s":
            self.site_state[i] = "reserved"
            rate, charge = self.f["rates"]["extractor_per_second"], None
        else:
            self.pond_state[i] = "reserved"
            rate = self.f["rates"]["extractor_per_second"] * self.f["rates"]["pond_multiplier"]
            charge = float(self.m.ponds[i]["charge"])

        def done(_s, kind=kind, i=i, rate=rate, charge=charge):
            if kind == "s":
                self.site_state[i] = "extractor"
            else:
                self.pond_state[i] = "extractor"
            self.incomes.append({"rate": rate, "charge": charge})

        return self.order_build(u, "nt_extractor", pos, on_done=done)

    def checkpoints(self) -> dict:
        return {t: round(self.series[t - 1], 1) for t in CHECKPOINTS if t <= len(self.series)}


# =============================================================================================
class Technocratic(World):
    """Labs on found sites. Policy: `energy_first` extractors before the first Lab, `extra_techs`
    Technicians trained beyond the starting two. Surveyors scout (and supply infrastructure); idle
    Technicians scout too and are pulled off when a site is known."""

    def decide(self) -> None:
        pol = self.policy
        techs = [u for u in self.units if u.kind == "tc_bioLight_builder"]
        want_techs = 2 + pol["extra_techs"]
        if len(techs) + self.queued("tc_bioLight_builder") < want_techs:
            self.queue_train(self.cc, "tc_bioLight_builder")
        energy_built = sum(1 for v in self.site_state if v == "extractor") + \
            sum(1 for v in self.pond_state if v in ("extractor", "reserved"))
        energy_pending = sum(1 for u in techs if u.task and u.task.get("type") == "build"
                             and u.task["structure"].kind == "nt_extractor")
        labs_wanted = self.free_sites() and energy_built + energy_pending >= pol["energy_first"]
        if labs_wanted and self.infra_spare < 50 and self.queued("tc_mechMedium_infrastructure") == 0:
            self.queue_train(self.cc, "tc_mechMedium_infrastructure")
        for u in self.units:
            if u.kind == "tc_mechMedium_infrastructure" and u.task is None:
                self.explore(u)
        for u in techs:
            busy = u.task is not None and u.task["type"] != "explore"
            if busy:
                continue
            energy_built = sum(1 for v in self.site_state if v == "extractor") + \
                sum(1 for v in self.pond_state if v in ("extractor", "reserved")) + \
                sum(1 for w in techs if w.task and w.task.get("type") == "build"
                    and w.task["structure"].kind == "nt_extractor")
            if energy_built < pol["energy_first"]:
                if self.build_extractor(u):
                    continue
            elif self.free_sites() and self._build_lab(u):
                continue
            elif not self.free_sites() and self.free_ponds() and self.build_extractor(u):
                continue
            if u.task is None:
                self.explore(u)

    def _build_lab(self, u: Unit) -> bool:
        sites = self.free_sites()
        if not sites or not self.can_pay("tc_dominionGen"):
            return False
        i = self.nearest(u.pos, [(i, self.m.sites[i][0]) for i in sites])
        self.site_state[i] = "reserved"

        def done(_s, i=i):
            self.site_state[i] = "lab"

        if not self.order_build(u, "tc_dominionGen", self.m.sites[i][0], on_done=done):
            self.site_state[i] = None
            return False
        return True

    def on_arrived(self, u: Unit, task: dict) -> None:
        pass  # an explorer re-targets next decide

    def dominion_rate(self) -> float:
        return self.f["rates"]["lab_per_second"] * sum(1 for v in self.site_state if v == "lab")


# =============================================================================================
class Colonial(World):
    """Stock Trucks run captives from shelters to Compounds. Policy: `compounds`, `trucks`,
    `compound_at` ("base" or "shelter" — beside the nearest shelter), `energy` extractors."""

    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        self.cells: list[list[float]] = []  # per Compound: release times of its occupants
        self.held: list[dict] = []  # captives serving: {"until": t}
        # Instrumentation: seconds trucks spent in each phase, and the size of each load.
        self.truck_phase: dict[str, float] = {}
        self.loads: list[int] = []
        order = sorted(range(len(self.shelters)),
                       key=lambda i: self.m.walk_distance(self.start, self.shelters[i]["pos"]))
        self.shelter_order = order

    def _compound_spot(self, n: int):
        if self.policy["compound_at"] == "base":
            sx, sz = self.start
            return (sx + 9 * (1 if n % 2 == 0 else -1), sz - 7 - 6 * (n // 2))
        shelter = self.shelters[self.shelter_order[n % len(self.shelters)]]["pos"]
        # Beside the shelter, on the side facing the start.
        dx, dz = self.start[0] - shelter[0], self.start[1] - shelter[1]
        d = math.hypot(dx, dz) or 1.0
        return (shelter[0] + 7 * dx / d, shelter[1] + 7 * dz / d)

    def decide(self) -> None:
        pol = self.policy
        servants = [u for u in self.units if u.kind == "cl_bioLight_builder"]
        compounds = [s for s in self.structures if s.kind == "cl_infrastructure"]
        for u in servants:
            if u.task is not None and u.task["type"] != "explore":
                continue
            if len(compounds) < pol["compounds"]:
                spot = self._compound_spot(len(compounds))
                if self.order_build(u, "cl_infrastructure", spot):
                    compounds = [s for s in self.structures if s.kind == "cl_infrastructure"]
                    continue
            energy = sum(1 for v in self.site_state if v == "extractor") + \
                sum(1 for v in self.pond_state if v in ("extractor", "reserved")) + \
                sum(1 for v in self.site_state if v == "reserved")
            if energy < pol["energy"] and self.build_extractor(u):
                continue
            if u.task is None:
                self.explore(u)
        trucks = [u for u in self.units if u.kind == "cl_mechLight_dominionGen"]
        if (len(trucks) + self.queued("cl_mechLight_dominionGen") < pol["trucks"]
                and self.has_tech("cl_mechLight_dominionGen")):
            self.queue_train(self.cc, "cl_mechLight_dominionGen")
        for u in trucks:
            if u.task is None:
                self._truck_next(u)

    def _done_compounds(self) -> list[Structure]:
        return [s for s in self.structures if s.kind == "cl_infrastructure" and s.done]

    def _truck_next(self, u: Unit) -> None:
        u.__dict__.setdefault("gave_up", False)
        cargo = u.__dict__.setdefault("cargo", 0)
        cap = self.f["colonial"]["truck_capacity"]
        if cargo >= cap or (cargo > 0 and u.__dict__.get("gave_up")):
            free = [s for s in self._done_compounds() if self._free(s) > 0]
            if not free:
                u.task = {"type": "wait", "left": 2}
                return
            j = self.nearest(u.pos, [(k, s.pos) for k, s in enumerate(free)])
            self.order_move(u, free[j].pos, then="deposit", compound=free[j])
            return
        # Next shelter: most residents not already claimed by another truck, nearest first.
        claimed = {id(t.task.get("shelter")) for t in self.units
                   if t is not u and t.task and t.task.get("type") in ("capture", "at_shelter")}
        best, best_score = None, -math.inf
        for s in self.shelters:
            d = self.m.walk_distance(u.pos, s["pos"])
            score = s["residents"] - (2 if id(s) in claimed else 0) - d / 40.0
            if score > best_score:
                best, best_score = s, score
        self.order_move(u, best["pos"], then="capture", shelter=best, waited=0)

    @staticmethod
    def _phase(u: Unit) -> str:
        t = u.task
        if t is None:
            return "idle (waiting for a free Compound place)" if u.__dict__.get("cargo") else "idle"
        if t["type"] == "capture":
            return "driving to a shelter"
        if t["type"] == "at_shelter":
            return "at the shelter (capturing / waiting for spawns)"
        if t["type"] == "deposit":
            return "driving to a Compound"
        if t["type"] == "wait":
            return "depositing" if u.__dict__.get("cargo", 0) == 0 else \
                "idle (waiting for a free Compound place)"
        return t["type"]

    def _queued(self) -> bool:
        return self.f["colonial"].get("processing", "simultaneous") == "queue"

    def _free(self, c: Structure) -> int:
        cap = self.f["colonial"]["compound_capacity"]
        if self._queued():
            q = c.state.setdefault("queue", [])  # ready times of captives waiting their turn
            serving = 1 if c.state.get("serving_until", -1) > self.t else 0
            return cap - len(q) - serving
        occ = c.state.setdefault("occupants", [])  # [start, end] of each sentence
        occ[:] = [x for x in occ if x[1] > self.t]
        return cap - len(occ)

    def _process_queues(self) -> None:
        """One-at-a-time processing: a Compound serves one captive's sentence, and the rest of
        its places hold captives waiting their turn (earning nothing while they wait)."""
        sentence = self.f["colonial"]["sentence_seconds"]
        for c in self._done_compounds():
            q = c.state.setdefault("queue", [])
            if c.state.get("serving_until", -1) <= self.t and q and q[0] <= self.t:
                q.pop(0)
                c.state["serving_until"] = self.t + sentence

    def _tick(self) -> None:
        if self._queued():
            self._process_queues()
        super()._tick()

    def _deposit_seconds(self, n: int) -> float:
        col = self.f["colonial"]
        return col["deposit_seconds"] + col.get("deposit_seconds_per_captive", 0.0) * n

    def on_arrived(self, u: Unit, task: dict) -> None:
        if task["type"] == "capture":
            # Stay at the shelter (see _advance) until full, or until it has given nothing for
            # a while while something is already aboard.
            u.task = {"type": "at_shelter", "shelter": task["shelter"], "idle": 0, "busy": 0.0}
            return
        if task["type"] == "deposit":
            # The truck stands at the Compound for the deposit interaction; the captives are
            # interned (and start paying) when it completes. Their places are held from arrival.
            c = task["compound"]
            n = min(self._free(c), u.cargo)
            wait = self._deposit_seconds(n) if n > 0 else 0.0
            start = self.t + math.ceil(wait)
            sentence = self.f["colonial"]["sentence_seconds"]
            if self._queued():
                c.state["queue"].extend([start] * n)
            else:
                c.state["occupants"].extend([[start, start + sentence]] * n)
            if n > 0:
                self.loads.append(n)
            u.cargo -= n
            u.gave_up = False
            if wait > 0:
                u.task = {"type": "wait", "left": wait}

    def _advance(self, u: Unit, dt: float) -> None:
        task = u.task
        if u.kind == "cl_mechLight_dominionGen":
            phase = self._phase(u)
            self.truck_phase[phase] = self.truck_phase.get(phase, 0.0) + dt
        if task is None or task["type"] != "at_shelter":
            super()._advance(u, dt)
            return
        cap = self.f["colonial"]["truck_capacity"]
        s = task["shelter"]
        if task["busy"] > 0:  # running one down
            task["busy"] -= dt
            return
        if u.cargo >= cap:
            u.task = None
            return
        if s["residents"] > 0:
            s["residents"] -= 1
            u.cargo += 1
            task["idle"] = 0
            task["busy"] = self.f["assumptions"]["capture_seconds_each"]
            return
        task["idle"] += 1
        if u.cargo > 0 and task["idle"] >= 12:
            u.gave_up = True
            u.task = None

    def dominion_rate(self) -> float:
        serving = 0
        for c in self._done_compounds():
            if self._queued():
                serving += 1 if c.state.get("serving_until", -1) > self.t else 0
                continue
            self._free(c)
            serving += sum(1 for s, e in c.state["occupants"] if s <= self.t < e)
        return serving * self.f["rates"]["compound_per_captive_per_second"]


# =============================================================================================
class Anarchical(World):
    """Followers standing with Warlords. Followers are not walked one by one: each is in a POOL —
    the base, or the camp of a liberator Warlord at a shelter — and a pool pays for as many as
    its Warlords can hold (followers_per_warlord each). Policy: `liberators` (Warlords sent to
    camp at the nearest shelters, liberating residents as they appear), `barracks` (Safehouse,
    then that many Redoubts training the cheapest BIO infantry), `strongholds` (extra Strongholds
    for Irregular throughput), `energy` extractors."""

    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        self.base_pool = sum(1 for u in self.units if self.p[u.kind]["frame"] == "BIO"
                             and u.kind != "an_bioMedium_dominionGen")
        self.camps: list[dict] = []  # {"shelter", "warlord": Unit, "pool": int}
        order = sorted(range(len(self.shelters)),
                       key=lambda i: self.m.walk_distance(self.start, self.shelters[i]["pos"]))
        self.shelter_order = order
        self.cap = self.f["assumptions"]["followers_per_warlord"]
        self.barracks_unit = min(
            (k for k in self.p["an_barracks"]["trains"] if self.p[k]["frame"] == "BIO"
             and not self.p[k]["requires"]),
            key=lambda k: self.p[k]["energy"])

    def _producers(self) -> list[Structure]:
        return [s for s in self.structures if s.kind == "an_commandCenter" and s.done]

    def decide(self) -> None:
        pol = self.policy
        warlords = [u for u in self.units if u.kind == "an_bioMedium_dominionGen"]
        base_warlords = [u for u in warlords if not u.__dict__.get("camp")]
        # Liberators: send idle base Warlords (beyond one kept home) to camp at shelters.
        while len(self.camps) < min(pol["liberators"], len(self.shelters)):
            spare = [w for w in base_warlords if w.task is None]
            if len(spare) <= 1:
                if self.queued("an_bioMedium_dominionGen") == 0:
                    self.queue_train(self.cc, "an_bioMedium_dominionGen")
                break
            w = spare[-1]
            shelter = self.shelters[self.shelter_order[len(self.camps)]]
            camp = {"shelter": shelter, "warlord": w, "pool": 0, "arrived": False}
            w.__dict__["camp"] = camp
            self.camps.append(camp)
            self.order_move(w, shelter["pos"], then="camp", camp=camp)
            base_warlords.remove(w)
        # Warlords at home for the base pool.
        if (self.base_pool > self.cap * len(base_warlords)
                and self.queued("an_bioMedium_dominionGen") == 0):
            self.queue_train(self.cc, "an_bioMedium_dominionGen")
        # Irregulars from every Stronghold, continuously.
        for s in self._producers():
            if not s.queue and s.job is None:
                self.queue_train(s, "an_bioLight_builder")
        # Barracks infantry.
        for s in self.structures:
            if s.kind == "an_barracks" and s.done and not s.queue and s.job is None:
                self.queue_train(s, self.barracks_unit)
        # Builders: a base Irregular leaves the pool for each errand.
        builders = [u for u in self.units if u.kind == "an_bioLight_builder"]
        idle = [u for u in builders if u.task is None]
        for u in idle:
            job = self._next_build(u)
            if job is None:
                break
            kind, pos = job
            if kind == "nt_extractor":
                ok = self.build_extractor(u)
            else:
                ok = self.order_build(u, kind, pos)
            if ok:
                self.base_pool -= 1
                u.__dict__["errand"] = True
            else:
                break

    def _next_build(self, u: Unit):
        pol = self.policy
        sx, sz = self.start
        have = lambda k: sum(1 for s in self.structures if s.kind == k)
        if pol["barracks"] > 0 and have("an_infrastructure") == 0:
            return ("an_infrastructure", (sx - 9, sz + 9))
        if have("an_barracks") < pol["barracks"] and self.has_tech("an_barracks"):
            return ("an_barracks", (sx + 9, sz + 9 + 5 * have("an_barracks")))
        if have("an_commandCenter") < 1 + pol["strongholds"]:
            return ("an_commandCenter", (sx - 10, sz - 10))
        energy = sum(1 for v in self.site_state if v in ("extractor", "reserved")) + \
            sum(1 for v in self.pond_state if v in ("extractor", "reserved"))
        if energy < pol["energy"] and (self.free_sites() or self.free_ponds()):
            return ("nt_extractor", None)
        return None

    def on_trained(self, u: Unit, s: Structure) -> None:
        if self.p[u.kind]["frame"] == "BIO" and u.kind != "an_bioMedium_dominionGen":
            self.base_pool += 1
            if u.kind != "an_bioLight_builder":
                self.units.remove(u)  # barracks infantry only ever stands in the pool

    def on_finished(self, s: Structure) -> None:
        pass

    def _advance(self, u: Unit, dt: float) -> None:
        if u.task is not None and u.task.get("type") == "rejoin":
            u.task["left"] -= dt
            if u.task["left"] <= 0:
                u.task = None
                u.pos = self.start
                self.base_pool += 1
            return
        was_building = u.task is not None and u.task.get("type") == "build"
        super()._advance(u, dt)
        if was_building and u.task is None and u.__dict__.get("errand"):
            # Walks home and rejoins the pool: the walk is a timer, not a path.
            u.__dict__["errand"] = False
            back = self.m.walk_distance(u.pos, self.start) / max(u.speed, 0.1)
            u.task = {"type": "rejoin", "left": back}

    def on_arrived(self, u: Unit, task: dict) -> None:
        if task["type"] == "camp":
            task["camp"]["arrived"] = True

    def _tick(self) -> None:
        # Liberation: an arrived liberator converts every resident of its shelter at once
        # (they wander within Wander.RADIUS = 3 of it; its LiberationRange is 4).
        for camp in self.camps:
            if camp["arrived"] and camp["shelter"]["residents"] > 0:
                camp["pool"] += camp["shelter"]["residents"]
                camp["shelter"]["residents"] = 0
        super()._tick()

    def dominion_rate(self) -> float:
        base_warlords = sum(1 for u in self.units if u.kind == "an_bioMedium_dominionGen"
                            and not u.__dict__.get("camp"))
        followers = min(self.base_pool, self.cap * base_warlords)
        for camp in self.camps:
            if camp["arrived"]:
                followers += min(camp["pool"], self.cap)
        return followers * self.f["rates"]["retinue_per_follower_per_second"]


# =============================================================================================
class Libertarian(World):
    """Opticons claiming the tiles in their vision. Canaries build a Relay (the Opticon's tech),
    then Opticons, each at the spot claiming the most unclaimed in-grid tiles. Policy:
    `extra_canaries` trained at the Shard, `energy` extractors."""

    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        r = self.f["libertarian"]["claim_radius"]
        self.claim_disk = MapData.disk(r).astype(np.float32)
        self.claimed = np.zeros((self.m.d, self.m.w), dtype=bool)  # by standing OR planned
        self.paying = np.zeros((self.m.d, self.m.w), dtype=bool)  # by standing Opticons
        self.own_fixtures = np.zeros((self.m.d, self.m.w), dtype=bool)
        self.candidates = np.zeros((self.m.d, self.m.w), dtype=bool)
        self.candidates[::3, ::3] = True
        self.candidates &= self.m.walkable
        self._gain = None
        for s in self.structures:
            self._mark_fixture(s)

    def _mark_fixture(self, s: Structure) -> None:
        fw, fd = self.p[s.kind]["footprint"]
        x0, z0 = int(s.pos[0] - fw / 2), int(s.pos[1] - fd / 2)
        self.own_fixtures[max(z0, 0):z0 + fd, max(x0, 0):x0 + fw] = True

    def _best_spot(self, pos):
        if self._gain is None:
            free = (~self.claimed).astype(np.float32)
            self._gain = fftconvolve(free, self.claim_disk, mode="same")
        g = np.where(self.candidates, self._gain, -1.0)
        z, x = np.unravel_index(int(np.argmax(g)), g.shape)
        return (x + 0.5, z + 0.5), float(g[z, x])

    def _claim(self, pos, mask: np.ndarray) -> None:
        self.m.stamp(mask, pos, MapData.disk(self.f["libertarian"]["claim_radius"]))
        self._gain = None

    def decide(self) -> None:
        pol = self.policy
        canaries = [u for u in self.units if u.kind == "lb_aircraftLight_builder"]
        if len(canaries) + self.queued("lb_aircraftLight_builder") < 2 + pol["extra_canaries"]:
            self.queue_train(self.cc, "lb_aircraftLight_builder")
        sx, sz = self.start
        for u in canaries:
            if u.task is not None:
                continue
            if self.count("lb_infrastructure", done_only=False) == 0:
                self.order_build(u, "lb_infrastructure", (sx + 9, sz - 9))
                continue
            energy = sum(1 for v in self.site_state if v in ("extractor", "reserved")) + \
                sum(1 for v in self.pond_state if v in ("extractor", "reserved"))
            if energy < pol["energy"] and self.build_extractor(u):
                continue
            if not self.has_tech("lb_dominion") or not self.can_pay("lb_dominion"):
                continue
            spot, gain = self._best_spot(u.pos)
            if gain < 1:
                continue
            self._claim(spot, self.claimed)

            def done(s, spot=spot):
                self._claim(spot, self.paying)

            self.order_build(u, "lb_dominion", spot, on_done=done)

    def on_finished(self, s: Structure) -> None:
        self._mark_fixture(s)

    def dominion_rate(self) -> float:
        cells = int(np.count_nonzero(self.paying & ~self.own_fixtures))
        return cells * self.f["rates"]["opticon_per_tile_per_second"]


FACTIONS = {
    "technocratic": Technocratic,
    "colonial": Colonial,
    "anarchical": Anarchical,
    "libertarian": Libertarian,
}

POLICIES = {
    "technocratic": [{"energy_first": k, "extra_techs": m}
                     for k in (0, 1, 2, 3, 5) for m in (0, 1, 2, 4)],
    "colonial": [{"compounds": c, "trucks": t, "compound_at": at, "energy": e}
                 for c in (2, 4, 6, 9, 12) for t in (2, 4, 6, 8) for at in ("base", "shelter")
                 for e in (0, 2)],
    "anarchical": [{"liberators": lib, "barracks": b, "strongholds": s, "energy": e}
                   for lib in (0, 1, 2, 3) for b in (0, 1) for s in (0, 1, 2) for e in (0, 2, 4)],
    "libertarian": [{"extra_canaries": c, "energy": e}
                    for c in (0, 2, 4, 6, 8, 12) for e in (0, 2, 4)],
}
