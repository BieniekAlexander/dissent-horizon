"""The paper model behind gdd/systems/combat/projectiles.md §Rocket calibration.

2D flight at 30 ticks/s, no jitter or terrain, mirroring EmissionPhase / PhasedLocomotion:

- A rocket is a list of STAGES (consecutive moving phases). Each steers at its target, turning at
  most `turn` deg/s. Speed follows the facing rule (gain `accel` toward `speed` while the target
  is ahead, lose it toward `min` while behind), or, with `bleed` > 0, gains
  `accel - bleed * angle_off_nose` each second, between `min` and `speed`. `burn`/`coast` cap the
  speed after `burn` seconds of the stage.
- A stage with `lead` > 0 aims at the intercept point predicted on its first tick with two
  samples of the target's motion, advanced by `lead`, and held; once that point is behind it, it
  flies straight.
- A steered stage takes over the speed it is handed; the first launches at `launch`.

The target starts across the line of fire at full speed and does one of:
  hold   — keeps its course;
  flee   — turns (at its own turn rate) to run directly away, from the moment of firing;
  reverse@T — reverses its course T seconds after firing: a reroute after the shot is away.

`escapes()` lists the firing distances (0.5 apart, out to reach) from which the target survives.

    python3 tools/projectiles/rocket_escape_model.py
prints the current rockets against the classes they are fired at.
"""
import math

DT = 1 / 30


def _wrap(a):
    return (a + math.pi) % (2 * math.pi) - math.pi


def _stage(**kw):
    s = dict(speed=0.0, turn=0.0, accel=0.0, min=0.0, bleed=0.0, lead=0.0, life=math.inf,
             burn=0.0, coast=0.0)
    s.update(kw)
    return s


def run(d, v, target_turn, behaviour, stages, launch, hit):
    """Seconds to a hit, or None if the rocket's last stage expires first."""
    rx = ry = rh = 0.0
    rs = launch
    tx, ty, th = d, 0.0, math.pi / 2
    want_th = th
    t = 0.0
    prev = None
    step = (0.0, 0.0)
    samples = 0
    for stage in stages:
        st = 0.0
        lead_point = None
        while st < stage["life"]:
            # target
            if behaviour == "flee":
                want_th = math.atan2(ty - ry, tx - rx)
            elif behaviour.startswith("reverse@") and t >= float(behaviour[8:]) and want_th == math.pi / 2:
                want_th = -math.pi / 2
            dl = _wrap(want_th - th)
            turn = math.radians(target_turn) * DT
            th += max(-turn, min(turn, dl))
            tx += v * math.cos(th) * DT
            ty += v * math.sin(th) * DT
            # measured target motion, on the rocket's own ticks
            if prev is not None:
                step = (tx - prev[0], ty - prev[1])
            prev = (tx, ty)
            samples += 1
            # aim
            goal = (tx, ty)
            if stage["lead"] > 0:
                if lead_point is None and samples >= 2:
                    lead_point = _intercept((rx, ry), (tx, ty), step, stage["speed"] * DT,
                                            stage["lead"])
                if lead_point is not None:
                    ahead = math.cos(rh) * (lead_point[0] - rx) + math.sin(rh) * (lead_point[1] - ry)
                    goal = lead_point if ahead > 0 else None
            if goal is not None and stage["turn"] > 0:
                off = _wrap(math.atan2(goal[1] - ry, goal[0] - rx) - rh)
                turn = math.radians(stage["turn"]) * DT
                rh += max(-turn, min(turn, off))
                if stage["bleed"] > 0:
                    rs = min(max(rs + (stage["accel"] - stage["bleed"] * abs(off)) * DT,
                                 stage["min"]), max(stage["speed"], stage["min"]))
                elif abs(off) <= math.pi / 2:
                    rs = min(rs + stage["accel"] * DT, stage["speed"])
                else:
                    rs = max(rs - stage["accel"] * DT, stage["min"])
            elif stage["turn"] <= 0:
                rs = stage["speed"]
            if stage["burn"] > 0 and st >= stage["burn"]:
                rs = min(rs, stage["coast"])
            rx += rs * math.cos(rh) * DT
            ry += rs * math.sin(rh) * DT
            t += DT
            st += DT
            if math.hypot(tx - rx, ty - ry) < hit:
                return t
    return None


def _intercept(origin, target, step, own_step, lead):
    dx, dy = target[0] - origin[0], target[1] - origin[1]
    ticks = math.hypot(dx, dy) / own_step if own_step > 0 else 0.0
    a = step[0] ** 2 + step[1] ** 2 - own_step ** 2
    b = 2 * (dx * step[0] + dy * step[1])
    c = dx * dx + dy * dy
    if abs(a) > 1e-12:
        disc = b * b - 4 * a * c
        if disc >= 0:
            r = math.sqrt(disc)
            for cand in sorted(((-b - r) / (2 * a), (-b + r) / (2 * a))):
                if cand > 0:
                    ticks = cand
                    break
    elif abs(b) > 1e-12 and -c / b > 0:
        ticks = -c / b
    return (target[0] + step[0] * ticks * lead, target[1] + step[1] * ticks * lead)


BEHAVIOURS = ("hold", "flee", "reverse@0.5")


def escapes(v, target_turn, reach, hit, behaviour, stages, launch):
    return [i / 2 for i in range(1, int(reach * 2) + 1)
            if run(i / 2, v, target_turn, behaviour, stages, launch, hit) is None]


def report(name, targets, reach, hit, stages, launch, behaviours=BEHAVIOURS):
    print(name)
    for label, v, target_turn in targets:
        cells = []
        for b in behaviours:
            e = escapes(v, target_turn, reach, hit, b, stages, launch)
            cells.append(f"{b}: {'never' if not e else f'{e[0]} ({len(e)}/{int(reach * 2)})'}")
        print(f"  {label:18} " + "   ".join(f"{c:24}" for c in cells))
    flight = run(reach, 0, 0, "hold", stages, launch, hit)
    print(f"  flight to {reach} at a standing target: {flight and round(flight, 2)} s")


if __name__ == "__main__":
    # Speeds are the classes of gdd/movement/speed_classes.md; target turn rates are the pieces'.
    ground = [("STEADY 2.2", 2.2, 90), ("BRISK 3", 3, 150), ("QUICK 4", 4, 180),
              ("FAST 5.25", 5.25, 180)]
    air = [("RAPID 7 air", 7, 90), ("SWIFT 9.3 air", 9.3, 140), ("BLAZING 12.4 air", 12.4, 213),
           ("HYPER 20 air", 20, 343)]
    report("Badger rocket", ground, 12, 0.7,
           [_stage(speed=16.5, turn=60, accel=40, min=2, life=2.2, burn=0.5, coast=9.3)],
           launch=2, behaviours=("hold", "flee"))
    report("Warlord rocket", ground + air[:3], 12, 0.7,
           [_stage(speed=16.5, turn=90, accel=10, min=2, bleed=120, lead=1, life=0.5),
            _stage(speed=16.5, turn=90, accel=10, min=2, bleed=120, life=3)],
           launch=8.25, behaviours=("hold", "flee", "reverse@0.3", "reverse@0.5", "reverse@1.0"))
    report("SAM missile", air, 20, 0.8,
           [_stage(speed=16.5, turn=180, accel=20, min=0.15, life=5)], launch=8.25,
           behaviours=("hold", "flee"))
