"""(1+2) evolution strategy. Mutates only the fields the screen showed move the
simulation more than the replication noise floor; think_interval_ticks is HELD at 20
because it gates build/scout/kamikaze cadence together with reaction time."""
import json, random, sys
from space import BASE, m

# field -> (lo, hi, is_int, sentinel_or_None)
LIVE = {
    "economy_reserve":               (0, 1500, True, None),
    "build_concurrency":             (1, 4, True, None),
    "production_structure_cap":      (1, 8, True, -1),   # -1 is a discrete extra level
    "utility_unit_cap":              (0, 6, True, None),
    "assumed_enemy_parity":          (0.0, 1.5, False, None),
    "retarget_switch_margin":        (1.0, 3.0, False, None),
    "retarget_weight_effectiveness": (0.0, 3.0, False, None),
    "attack_value_ratio":            (0.8, 2.5, False, None),
    "army_commit_threshold":         (1, 12, True, None),
}
SIGMA = 0.20  # of each field's range

def mutate(parent, rng):
    c = dict(parent)
    for f, (lo, hi, isint, sent) in LIVE.items():
        if f == "production_structure_cap":
            # sentinel handled as a separate categorical level, never interpolated through
            if rng.random() < 0.25:
                c[f] = -1 if c[f] != -1 else rng.randint(lo, hi)
                continue
            cur = c[f] if c[f] != -1 else hi
        else:
            cur = c[f]
        v = cur + rng.gauss(0, SIGMA * (hi - lo))
        v = max(lo, min(hi, v))
        c[f] = int(round(v)) if isint else round(v, 3)
    return c

def gen_batch(parent, gen, n, rng):
    out, cands = [], []
    for k in range(n):
        cand = mutate(parent, rng)
        cands.append(cand)
        out.append(m("es_g%d_c%d_A0" % (gen, k), 11, cand, parent))
        out.append(m("es_g%d_c%d_A1" % (gen, k), 11, parent, cand))
    return out, cands

if __name__ == "__main__":
    gen = int(sys.argv[1])
    rng = random.Random(20260905 + gen)
    parent = json.load(open("es_parent_g%d.json" % gen)) if gen > 1 else dict(BASE)
    if gen == 1:
        json.dump(parent, open("es_parent_g1.json", "w"))
    batch, cands = gen_batch(parent, gen, 2, rng)
    json.dump(batch, open("es_g%d.json" % gen, "w"))
    json.dump(cands, open("es_cands_g%d.json" % gen, "w"))
    print("gen %d: %d matches, %d candidates" % (gen, len(batch), len(cands)))
