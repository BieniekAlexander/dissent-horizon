import math

import pytest

from dh_balance.combat import (
    dps,
    exchange_cost,
    is_favorable,
    time_to_kill,
)
from dh_balance.loader import load_world


def world():
    return load_world()


def get(w, uid):
    return w.get(uid)


def test_shots_per_second_single_clip():
    w = world()
    cannon = get(w, "iron_regime:heavy_tank").weapons[0]
    # split_time=45 ticks, clip_size=1, 30 ticks/sec -> 30/45 shots/sec
    assert cannon.shots_per_second() == pytest.approx(30.0 / 45.0)


def test_lead_is_terrible_vs_heavy():
    w = world()
    conscript = get(w, "iron_regime:conscript")   # LEAD rifle
    tank = get(w, "iron_regime:heavy_tank")        # HEAVY
    # LEAD vs HEAVY multiplier is 0.1 -> very low dps
    assert dps(w.damage, conscript, tank) < dps(w.damage, conscript, get(w, "sky_nomads:raider"))


def test_ground_weapon_cannot_hit_air_is_infinite_ttk():
    w = world()
    tank = get(w, "iron_regime:heavy_tank")   # cannon hits ground only
    gunship = get(w, "sky_nomads:gunship")     # air
    assert math.isinf(time_to_kill(w.damage, tank, gunship))
    assert math.isinf(exchange_cost(w.damage, tank, gunship))


def test_gunship_is_unanswered_by_regime():
    w = world()
    gunship = get(w, "sky_nomads:gunship")
    # No iron_regime unit can hit air -> none favorable.
    regime_units = [u for u in w.factions["iron_regime"].units() if u.is_combatant]
    assert all(not is_favorable(w.damage, r, gunship) for r in regime_units)


def test_exchange_cost_symmetry_direction():
    w = world()
    # A heavy tank should be a more cost-efficient answer to a raider than the
    # reverse (raiders chip a heavy tank very slowly with LEAD).
    tank = get(w, "iron_regime:heavy_tank")
    raider = get(w, "sky_nomads:raider")
    assert exchange_cost(w.damage, tank, raider) < exchange_cost(w.damage, raider, tank)


def test_frame_multiplier_scales_damage_per_shot():
    from dh_balance.combat import damage_per_shot
    from dh_balance.model import (
        Armour, Buildable, Cost, DamageTable, DamageType, Frame, Layer,
        Projectile, Weapon,
    )
    # LAZER doubles vs METALLIC, halves vs BIOLOGICAL; armour neutral so only
    # the frame axis moves.
    table = DamageTable(
        vs_armour={}, vs_attribute={},
        vs_frame={DamageType.LAZER: {Frame.METALLIC: 2.0, Frame.BIOLOGICAL: 0.5}},
    )
    weapon = Weapon(id="w", name="w", split_time=1, reload_time=1, clip_size=1,
                    reach=1.0, hits=frozenset({Layer.GROUND}),
                    projectile=Projectile(id="p", base_damage=100.0,
                                          damage_type=DamageType.LAZER))

    def dummy(frame):
        return Buildable(faction="f", id="t", kind="unit", name="t", cost=Cost(),
                         armour=Armour.MEDIUM, frame=frame, hp=100.0, layer=Layer.GROUND)

    assert damage_per_shot(table, weapon, dummy(Frame.METALLIC)) == 200.0
    assert damage_per_shot(table, weapon, dummy(Frame.BIOLOGICAL)) == 50.0
    # No frame on the target -> frame axis is a no-op (multiplier 1.0).
    none_frame = dummy(Frame.METALLIC)
    none_frame.frame = None
    assert damage_per_shot(table, weapon, none_frame) == 100.0
