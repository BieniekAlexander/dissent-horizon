"""The paper model behind gdd/systems/combat/projectiles.md §Rocket calibration.

2D pure pursuit at 30 ticks/s, no jitter or terrain. The target starts across the line of fire
at full speed and evades in either of two ways: holding its course, or turning (at its own turn
rate) to flee directly away. A rocket accelerates from its launch speed to `speed`, and after
`burn` seconds is held to `coast`. `escapes()` lists the firing distances (0.5 apart, out to
reach) from which some evasion outlives the rocket.

    python3 tools/projectiles/rocket_escape_model.py
prints the current rockets against the classes they are fired at.
"""
import math

DT = 1 / 30


def run(d, v, target_turn, flee, speed, turn, life, launch, accel, burn, coast, hit):
    """Seconds to a hit, or None if the rocket expires first."""
    rx = ry = rh = 0.0
    rs = launch
    tx, ty, th = d, 0.0, math.pi / 2
    t = 0.0
    while t < life:
        if flee:
            want = math.atan2(ty - ry, tx - rx)
            delta = (want - th + math.pi) % (2 * math.pi) - math.pi
            step = math.radians(target_turn) * DT
            th += max(-step, min(step, delta))
        tx += v * math.cos(th) * DT
        ty += v * math.sin(th) * DT
        cap = speed if t < burn else coast
        rs = min(cap, rs + accel * DT)
        want = math.atan2(ty - ry, tx - rx)
        delta = (want - rh + math.pi) % (2 * math.pi) - math.pi
        step = math.radians(turn) * DT
        rh += max(-step, min(step, delta))
        rx += rs * math.cos(rh) * DT
        ry += rs * math.sin(rh) * DT
        t += DT
        if math.hypot(tx - rx, ty - ry) < hit:
            return t
    return None


def escapes(v, target_turn, reach, hit, **rocket):
    out = []
    for i in range(1, int(reach * 2) + 1):
        d = i / 2
        if any(run(d, v, target_turn, flee, hit=hit, **rocket) is None for flee in (False, True)):
            out.append(d)
    return out


def report(name, targets, reach, hit, **rocket):
    print(name)
    for label, v, target_turn in targets:
        e = escapes(v, target_turn, reach, hit, **rocket)
        where = "never" if not e else f"{e[0]} ({len(e)} of {int(reach * 2)} distances)"
        flight = run(reach, 0, 0, False, hit=hit, **rocket)
        print(f"  {label:16} escapes from {where:24} flight to {reach}: {flight and round(flight, 2)} s")


if __name__ == "__main__":
    # Speeds are the classes of gdd/movement/speed_classes.md; target turn rates are the pieces'.
    ground = [("STEADY 2.2", 2.2, 90), ("BRISK 3", 3, 150), ("QUICK 4", 4, 180),
              ("FAST 5.25", 5.25, 180), ("RAPID 7 ground", 7, 180)]
    air = [("RAPID 7 air", 7, 90), ("SWIFT 9.3 air", 9.3, 140), ("BLAZING 12.4 air", 12.4, 213),
           ("HYPER 20 air", 20, 343)]
    report("Badger rocket", ground, 12, 0.7, speed=16.5, turn=60, life=2.2, launch=2,
           accel=40, burn=0.5, coast=9.3)
    report("Warlord rocket", ground + air[:2], 12, 0.7, speed=5.25, turn=180, life=5,
           launch=2.625, accel=2.25, burn=99, coast=5.25)
    report("SAM missile", air, 20, 0.8, speed=16.5, turn=180, life=5, launch=8.25,
           accel=20, burn=99, coast=16.5)
