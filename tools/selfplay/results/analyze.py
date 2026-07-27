"""Shared scoring + statistics for the self-play experiment."""
import json, math

CAP = 1200.0

def load(path):
    rows = []
    for line in open(path):
        line = line.strip()
        if line:
            rows.append(json.loads(line))
    return rows

def material(sample_slot):
    """MY SHAPING CHOICE: energy-equivalent material for the stalemate tie-break.
    Army value + banked energy + a flat 250 energy per standing structure."""
    return (sample_slot.get("army_energy_value", 0.0)
            + sample_slot.get("energy", 0.0)
            + 250.0 * sample_slot.get("structure_count", 0))

def score(row, slot):
    """Objective from `slot`'s point of view, in [0,1]. MY SHAPING CHOICE.
    Any win (0.75-1.00) > any stalemate (0.25-0.75) > any loss (0.00-0.25).
    Within a win, sooner is better; within a loss, later is better."""
    if not row.get("ok"):
        return None
    o = row.get("outcome"); t = row.get("simulated_seconds", CAP); f = min(1.0, t / CAP)
    if o == "elimination":
        if row.get("winner") == slot:
            return 0.75 + 0.25 * (1.0 - f)
        return 0.25 * f
    if o == "mutual_elimination":
        return 0.5
    # stalemate / wall_clock_cap: shaped fallback on final-sample material margin
    ss = row.get("samples") or []
    if not ss:
        return 0.5
    fin = ss[-1]["slots"]
    a = material(fin[slot]); b = material(fin[1 - slot])
    m = (a - b) / (a + b + 1.0)          # in [-1, 1]
    return 0.25 + 0.5 * ((m + 1.0) / 2.0)

def win(row, slot):
    """Bernoulli outcome for slot: 1 win, 0 loss, None for draw/stalemate (excluded)."""
    if not row.get("ok"):
        return None
    o = row.get("outcome")
    if o == "elimination":
        return 1 if row.get("winner") == slot else 0
    return None

def wilson(k, n, z=1.96):
    if n == 0:
        return (0.0, 1.0)
    p = k / n; d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))

def mean_ci(xs, z=1.96):
    """Mean with a normal-approx CI; honest enough at n>=4 and flagged as such."""
    n = len(xs)
    if n == 0: return (float("nan"), float("nan"), float("nan"))
    m = sum(xs) / n
    if n < 2: return (m, float("nan"), float("nan"))
    v = sum((x - m) ** 2 for x in xs) / (n - 1)
    se = math.sqrt(v / n)
    return (m, m - z * se, m + z * se)

def diff_prop_ci(k1, n1, k2, n2, z=1.96):
    """CI on p1 - p2 (Agresti-Caffo: add 1 success and 1 failure to each arm)."""
    if n1 == 0 or n2 == 0: return (float("nan"),) * 3
    p1 = (k1 + 1) / (n1 + 2); p2 = (k2 + 1) / (n2 + 2)
    se = math.sqrt(p1 * (1 - p1) / (n1 + 2) + p2 * (1 - p2) / (n2 + 2))
    d = k1 / n1 - k2 / n2
    return (d, (p1 - p2) - z * se, (p1 - p2) + z * se)

def n_for_effect(delta, p=0.5, z=1.96, power_z=0.84):
    """Matches PER ARM to resolve a win-rate shift of `delta` from p at 95%/80%."""
    if delta <= 0: return float("inf")
    return math.ceil(((z + power_z) ** 2) * 2 * p * (1 - p) / (delta ** 2))

def series(row, slot, key="army_energy_value"):
    return [s["slots"][slot].get(key, 0.0) for s in row["samples"]]

def traj_distance(a, b, slot=0):
    """Mean absolute difference between two matches' slot-0 army-value series,
    normalised by the pooled mean. The unit the noise floor is measured in."""
    x = series(a, slot); y = series(b, slot)
    n = min(len(x), len(y))
    if n == 0: return float("nan")
    x, y = x[:n], y[:n]
    scale = (sum(x) + sum(y)) / (2 * n) + 1.0
    return sum(abs(p - q) for p, q in zip(x, y)) / n / scale
