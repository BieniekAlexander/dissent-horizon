"""Unit tests for the emergent matchup factors. Each factor is exercised in
isolation with hand-built units so a tuning change is easy to pin down."""
from dh_balance import combat
from dh_balance import effectiveness as eff
from dh_balance.model import (
    Armour, Buildable, Cost, DamageTable, DamageType, Layer, Projectile, Weapon,
)

TABLE = DamageTable(vs_armour={}, vs_attribute={}, vs_frame={})   # all multipliers 1.0


def weapon(reach=1.0, hits=(Layer.GROUND,), base_damage=50.0,
           proj_speed=0.0, aoe=0.0, projectile=True):
    p = Projectile(id="p", base_damage=base_damage, damage_type=DamageType.LEAD,
                   speed=proj_speed, aoe_radius=aoe) if projectile else None
    return Weapon(id="w", name="w", split_time=1, reload_time=1, clip_size=1,
                  reach=reach, hits=frozenset(hits), projectile=p,
                  melee_damage=0.0 if projectile else base_damage)


def unit(speed=0.0, hp=100.0, cost=100, layer=Layer.GROUND, weapons=None):
    return Buildable(faction="f", id="u", kind="unit", name="u", cost=Cost(ore=cost),
                     armour=Armour.MEDIUM, hp=hp, layer=layer, speed=speed,
                     weapons=weapons if weapons is not None else [weapon()])


def test_factor_can_hit_gates_air():
    ground_only = unit(weapons=[weapon(hits=(Layer.GROUND,))])
    air_target = unit(layer=Layer.AIR)
    assert eff.factor_can_hit(ground_only, air_target) == 0.0
    assert eff.factor_can_hit(ground_only, unit(layer=Layer.GROUND)) == 1.0


def test_factor_relative_speed_bounds_and_direction():
    fast, slow = unit(speed=0.1), unit(speed=0.05)
    assert eff.factor_relative_speed(fast, slow) > 1.0
    assert eff.factor_relative_speed(slow, fast) < 1.0
    assert eff.factor_relative_speed(fast, fast) == 1.0
    assert eff.factor_relative_speed(unit(speed=0.0), fast) == 1.0   # immobile -> neutral
    # bounded to 1 ± SPEED_EDGE
    assert eff.factor_relative_speed(unit(speed=1.0), unit(speed=1e-6)) <= 1.0 + eff.SPEED_EDGE + 1e-9


def test_factor_relative_range_direction():
    long = unit(weapons=[weapon(reach=10.0)])
    short = unit(weapons=[weapon(reach=2.0)])
    assert eff.factor_relative_range(TABLE, long, short) > 1.0
    assert eff.factor_relative_range(TABLE, short, long) < 1.0


def test_factor_dodge_fast_target_vs_slow_projectile():
    attacker = unit(weapons=[weapon(proj_speed=0.1)])
    assert eff.factor_dodge(TABLE, attacker, unit(speed=0.05)) < 1.0   # moving target dodges
    assert eff.factor_dodge(TABLE, attacker, unit(speed=0.0)) == 1.0   # stationary can't dodge
    melee = unit(weapons=[weapon(projectile=False)])
    assert eff.factor_dodge(TABLE, melee, unit(speed=0.05)) == 1.0     # nothing to dodge


def test_factor_overkill_penalises_alpha_strike():
    sniper = unit(weapons=[weapon(base_damage=1000.0)])
    assert eff.factor_overkill(TABLE, sniper, unit(hp=100.0)) < 1.0    # 900 wasted
    assert eff.factor_overkill(TABLE, sniper, unit(hp=100.0)) >= eff.OVERKILL_FLOOR
    rightsized = unit(weapons=[weapon(base_damage=50.0)])
    assert eff.factor_overkill(TABLE, rightsized, unit(hp=100.0)) == 1.0


def test_factor_aoe_rewards_splash_vs_cheap_targets():
    splasher = unit(weapons=[weapon(aoe=3.0)])
    assert eff.factor_aoe(TABLE, splasher, unit(cost=50)) > 1.0        # cheap swarm
    no_aoe = unit(weapons=[weapon(aoe=0.0)])
    assert eff.factor_aoe(TABLE, no_aoe, unit(cost=50)) == 1.0


def test_combined_factor_zero_when_cannot_engage():
    ground_only = unit(weapons=[weapon(hits=(Layer.GROUND,))])
    assert eff.combined_factor(TABLE, ground_only, unit(layer=Layer.AIR)) == 0.0


def test_effective_exchange_cost_reflects_aoe_edge():
    # Two identical stationary turrets, except the response has splash. The AoE
    # factor should make it a cheaper answer than the raw DPS race implies.
    threat = unit(speed=0.0, cost=50, weapons=[weapon()])
    response = unit(speed=0.0, cost=50, weapons=[weapon(aoe=3.0)])
    base = combat.exchange_cost(TABLE, response, threat)
    effective = eff.effective_exchange_cost(TABLE, response, threat)
    assert effective < base
