"""Unit tests for the faction-distinctness heuristics."""
from dh_balance import distinctness as dn
from dh_balance.loader import load_world
from dh_balance.model import (
    Armour, Buildable, Cost, DamageTable, DamageType, Frame, Layer, Projectile, Weapon,
)

# LEAD favours LIGHT, LAZER favours HEAVY (opposite ends); TOXIN is neutral.
TABLE = DamageTable(
    vs_armour={
        DamageType.LEAD: {Armour.LIGHT: 1.0, Armour.MEDIUM: 0.5, Armour.HEAVY: 0.1},
        DamageType.LAZER: {Armour.LIGHT: 0.1, Armour.MEDIUM: 0.75, Armour.HEAVY: 1.5},
        DamageType.TOXIN: {Armour.LIGHT: 1.0, Armour.MEDIUM: 1.0, Armour.HEAVY: 1.0},
    },
    vs_attribute={}, vs_frame={},
)


def wpn(reach=1.0, hits=(Layer.GROUND,), dtype=DamageType.LEAD, melee=False):
    proj = None if melee else Projectile(id="p", base_damage=10.0, damage_type=dtype)
    return Weapon(id="w", name="w", split_time=1, reload_time=1, clip_size=1,
                  reach=reach, hits=frozenset(hits), projectile=proj,
                  melee_damage=0.0 if not melee else 10.0, melee_damage_type=dtype)


def unit(uid="u", weapons=None, frame=Frame.BIOLOGICAL, armour=Armour.LIGHT,
         speed=0.05, cost=100, layer=Layer.GROUND):
    return Buildable(faction="f", id=uid, kind="unit", name=uid, cost=Cost(ore=cost),
                     armour=armour, frame=frame, hp=100.0, layer=layer, speed=speed,
                     weapons=weapons if weapons is not None else [wpn()])


# --- weapon_difference ------------------------------------------------------ #
def test_weapon_difference_target_coverage():
    ground = wpn(hits=(Layer.GROUND,))
    air = wpn(hits=(Layer.AIR,))
    both = wpn(hits=(Layer.GROUND, Layer.AIR))
    assert dn.weapon_difference(TABLE, ground, air) == dn.TARGET_DISJOINT      # disjoint
    assert dn.weapon_difference(TABLE, ground, both) == dn.TARGET_PARTIAL      # overlap, not equal
    assert dn.weapon_difference(TABLE, ground, wpn()) == 0.0                   # identical


def test_weapon_difference_reach_buckets():
    assert dn.weapon_difference(TABLE, wpn(reach=1.0), wpn(reach=10.0)) == 2 * dn.BUCKET_STEP


def test_weapon_difference_damage_type():
    lead, lazer = wpn(dtype=DamageType.LEAD), wpn(dtype=DamageType.LAZER)
    toxin = wpn(dtype=DamageType.TOXIN)
    assert dn.weapon_difference(TABLE, lead, lazer) == dn.DAMAGE_TYPE_DIFF + dn.DAMAGE_GREATLY_DIFF
    assert dn.weapon_difference(TABLE, lead, toxin) == dn.DAMAGE_TYPE_DIFF      # differ, not greatly


def test_damage_types_greatly_differ():
    assert dn.damage_types_greatly_differ(TABLE, DamageType.LEAD, DamageType.LAZER)
    assert not dn.damage_types_greatly_differ(TABLE, DamageType.LEAD, DamageType.TOXIN)
    assert not dn.damage_types_greatly_differ(TABLE, DamageType.LEAD, DamageType.LEAD)


# --- unit-level differences ------------------------------------------------- #
def test_loadout_difference_overlap_and_unarmed():
    a = unit(weapons=[wpn(dtype=DamageType.LEAD), wpn(dtype=DamageType.LAZER)])
    b = unit(weapons=[wpn(dtype=DamageType.TOXIN), wpn(dtype=DamageType.LEAD)])
    assert dn.loadout_difference(TABLE, a, b) == 0.0          # both field a LEAD gun
    assert dn.loadout_difference(TABLE, unit(weapons=[]), unit()) == dn.UNARMED_VS_ARMED
    assert dn.loadout_difference(TABLE, unit(weapons=[]), unit(weapons=[])) == 0.0


def test_defense_difference():
    assert dn.defense_difference(unit(frame=Frame.BIOLOGICAL), unit(frame=Frame.METALLIC)) == dn.FRAME_DIFF
    assert dn.defense_difference(unit(armour=Armour.LIGHT), unit(armour=Armour.HEAVY)) == 2 * dn.BUCKET_STEP
    assert dn.defense_difference(unit(), unit()) == 0.0


def test_movement_difference():
    assert dn.movement_difference(unit(layer=Layer.AIR), unit(layer=Layer.GROUND)) == dn.AERIAL_VS_GROUND
    assert dn.movement_difference(unit(speed=0.01), unit(speed=0.2)) == 2 * dn.BUCKET_STEP
    assert dn.movement_difference(unit(), unit()) == 0.0


def test_expensiveness_difference():
    assert dn.expensiveness_difference(unit(cost=50), unit(cost=500)) == 2 * dn.BUCKET_STEP
    assert dn.expensiveness_difference(unit(cost=100), unit(cost=120)) == 0.0


def test_unit_distinctness_identical_is_zero():
    assert dn.unit_distinctness(TABLE, unit(), unit()) == 0.0


# --- set-level -------------------------------------------------------------- #
def test_set_distinctness_is_asymmetric():
    twin = unit(uid="a")
    other = unit(uid="b", armour=Armour.HEAVY, frame=Frame.METALLIC, cost=500,
                 weapons=[wpn(dtype=DamageType.LAZER, reach=10.0)])
    a = [twin]
    b = [unit(uid="a2"), other]              # contains a twin of `twin` plus a very different unit
    assert dn.set_distinctness(TABLE, a, b) == 0.0      # twin is perfectly shadowed
    assert dn.set_distinctness(TABLE, b, a) > 0.0       # `other` has no analogue in a


def test_most_similar_pair_finds_the_twins():
    a = [unit(uid="a", armour=Armour.HEAVY)]
    b = [unit(uid="b_far", armour=Armour.LIGHT, cost=500), unit(uid="b_twin", armour=Armour.HEAVY)]
    pair = dn.most_similar_pair(TABLE, a, b)
    assert pair is not None and pair.unit_b == "f:b_twin" and pair.distinctness == 0.0


def test_set_distinctness_of_roster_against_itself_is_zero():
    w = load_world()
    units = w.factions["iron_regime"].units()
    assert dn.set_distinctness(w.damage, units, units) == 0.0


# --- query integration ------------------------------------------------------ #
def test_faction_distinctness_and_matrix_on_fixture():
    from dh_balance import queries
    w = load_world()
    r = queries.faction_distinctness(w, "iron_regime", "sky_nomads")
    assert r.a_to_b >= 0.0 and r.b_to_a >= 0.0
    assert r.most_similar is not None
    m = queries.distinctness_matrix(w)
    assert ("iron_regime", "sky_nomads") in m
    assert ("iron_regime", "iron_regime") not in m       # no diagonal
