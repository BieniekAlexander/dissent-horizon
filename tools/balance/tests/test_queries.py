from dh_balance import graph
from dh_balance.loader import load_world
from dh_balance.queries import obsolete_units, tech_tier_gap, unanswered_threats


def world():
    return load_world()


def test_militia_is_obsolete():
    w = world()
    res = obsolete_units(w, "iron_regime")
    obsolete = {d.unit for d in res}
    assert "iron_regime:militia" in obsolete          # dominated by conscript
    assert "iron_regime:heavy_tank" not in obsolete    # frontier
    assert "iron_regime:conscript" not in obsolete


def test_gunship_unanswered_by_regime():
    w = world()
    res = unanswered_threats(w, "sky_nomads", "iron_regime")
    threats = {u.threat: u for u in res}
    assert "sky_nomads:gunship" in threats
    assert threats["sky_nomads:gunship"].reason == "no_weapon_can_hit"


def test_regime_can_answer_ground_units():
    w = world()
    # Regime -> Sky raider/saboteur: regime has ground answers, so they should
    # NOT all be unanswered. (At minimum the heavy tank answers them.)
    res = unanswered_threats(w, "sky_nomads", "iron_regime")
    unanswered = {u.threat for u in res}
    assert "sky_nomads:raider" not in unanswered


def test_tech_tiers():
    w = world()
    tiers = graph.tech_tiers(w.factions["sky_nomads"])
    assert tiers["outpost"] == 1
    assert tiers["compound"] == 2
    assert tiers["airpad"] == 3
    assert tiers["gunship"] == 4   # requires airpad (T3) -> T4


def test_tier_gap_hides_gunship_when_high_capped_low():
    w = world()
    # If Sky is capped below the gunship's tier, it isn't in the threat pool.
    r = tech_tier_gap(w, "iron_regime", 9, "sky_nomads", 3)
    assert all("gunship" not in u.threat for u in r.struggles_against)
    # But allowed at a high enough cap, and Regime still can't answer it.
    r2 = tech_tier_gap(w, "iron_regime", 9, "sky_nomads", 4)
    assert any("gunship" in u.threat for u in r2.struggles_against)
