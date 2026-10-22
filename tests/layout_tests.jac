"""Procedural long-range ridges: deterministic per seed, varied across seeds, always valid, fair and private."""
import json;
import math;
import tempfile;
import from game.aim { release_pull, release_long, long_pointer, LONG_W, LONG_V_MAX }
import from game.layout { geometry_faults, settle_drift, ridge_name, ground_at }
import from game.longrange {
    free_flight, generate_long, make_long_terrain, long_exposure, long_kills, long_scripted_contact, long_scripted_breaks,
    LONG_EXPOSURE_MIN, LONG_EXPOSURE_MAX, LONG_EXPOSURE_GAP
}
import from game.practice_bot { aim_sigma, long_sigma, choose, learn, new_memory }
import from server.live { boot_match, claim_player, rematch_room, take_shot, watch }

glob SECRET: str = "layout-test-secret";
glob SAMPLE: list[dict[str, any]] = [];

glob FALLBACKS: list[int] = [];

# Same deterministic fallback chain as server.live: a ridge with no fair layout hands over to the next.
def _generate(ridge: int) -> dict[str, any] {
    wanted = ridge;
    for attempt in range(6) {
        layout = generate_long(wanted, SECRET);
        if len(layout) > 0 {
            return layout;
        }
        FALLBACKS.append(ridge);
        wanted = (wanted * 7919 + 13) % 99999 + 1;
    }
    return {};
}

def _sample() -> list[dict[str, any]] {
    if len(SAMPLE) == 0 {
        for ridge in range(1, 41) {
            SAMPLE.append(_generate(ridge * 977 + 13));
        }
    }
    return SAMPLE;
}

def _find(layout: dict[str, any], pid: str) -> dict[str, any] {
    for piece in layout["pieces"] {
        if str(piece["id"]) == pid {
            return piece;
        }
    }
    return {};
}

def _signature(layout: dict[str, any]) -> str {
    a = _find(layout, "core-a");
    b = _find(layout, "core-b");
    return json.dumps([layout["launcher_a"], round(float(a["x"]), 2), round(float(a["y"]), 2),
        round(float(b["x"]), 2), round(float(b["y"]), 2), len(layout["pieces"]),
        [round(float(p[1]), 2) for p in layout["terrain"][::8]]]);
}

def _pull(live: any, player: str, command: str, pointer: list[float], weapon: str) -> dict[str, any] {
    return json.loads(take_shot(live, player, command, float(pointer[0]), float(pointer[1]), 800.0, 400.0, 1.0,
        live.table.epoch, live.table.turn, live.table.revision, weapon));
}

def _quiet(layout: dict[str, any], seat: str) -> list[float] {
    # A steep, gentle lob that comes down a few metres in front of the shooter's own launcher.
    angle = math.radians(72.0) if seat == "A" else math.pi - math.radians(72.0);
    return long_pointer(seat, angle, 5.0);
}

def _seated(ridge: int) -> any {
    live = boot_match(tempfile.mkdtemp(prefix="fogshot-ridge-"), "fogshot", ridge);
    assert claim_player(live, "player-a").seat == "A";
    assert claim_player(live, "player-b").seat == "B";
    return live;
}

test "the same ridge and secret always rebuild the same layout" {
    first = generate_long(48213, SECRET);
    assert len(first) > 0;
    assert first["mode"] == "long" and first["width"] == LONG_W;
    assert json.dumps(first, sort_keys=True) == json.dumps(generate_long(48213, SECRET), sort_keys=True);
    assert first["name"] == ridge_name(48213);
    assert "#48213" in first["name"];
    # A different server secret gives a different hidden layout for the same public ridge.
    other = generate_long(48213, "another-server");
    assert _signature(other) != _signature(first);
    assert make_long_terrain(77) == make_long_terrain(77);
    assert make_long_terrain(77) != make_long_terrain(78);
}

test "forty ridges give forty distinct layouts" {
    layouts = _sample();
    assert all([len(layout) > 0 for layout in layouts]);
    signatures = set([_signature(layout) for layout in layouts]);
    assert len(signatures) == 40;
    assert len(set(FALLBACKS)) <= 8;
    cores = set([round(float(_find(layout, "core-b")["x"]), 1) for layout in layouts]);
    launchers = set([float(layout["launcher_a"][0]) for layout in layouts]);
    assert len(cores) >= 15;
    assert len(launchers) >= 20;
    hills = set([round(max([float(p[1]) for p in layout["terrain"]]), 0) for layout in layouts]);
    assert len(hills) >= 5;
    roles = set();
    for layout in layouts {
        for piece in layout["pieces"] {
            roles.add(str(piece["role"]));
        }
    }
    assert "timber" in roles and "stone" in roles;
}

test "every generated layout is long range, valid, stable, reachable and balanced" {
    for layout in _sample() {
        assert geometry_faults(layout) == [];
        rate_a = long_exposure(layout, "A")[0];
        rate_b = long_exposure(layout, "B")[0];
        assert rate_a >= LONG_EXPOSURE_MIN and rate_a <= LONG_EXPOSURE_MAX;
        assert rate_b >= LONG_EXPOSURE_MIN and rate_b <= LONG_EXPOSURE_MAX;
        assert abs(rate_a - rate_b) <= LONG_EXPOSURE_GAP + 0.0001;
        assert len(layout["proof"]["A"]) == 2 and len(layout["proof"]["B"]) == 2;
        # Terrain is mirrored (public); both launchers sit on the same height.
        assert layout["launcher_a"][1] == layout["launcher_b"][1];
        assert abs(ground_at(layout["terrain"], 30.0) - ground_at(layout["terrain"], LONG_W - 30.0)) < 0.0001;
        # Artillery scale: launchers ~130-150 m apart, every core 85+ m from the enemy launcher.
        gap = float(layout["launcher_b"][0]) - float(layout["launcher_a"][0]);
        assert gap >= 130.0 and gap <= 150.0;
        core_a = _find(layout, "core-a");
        core_b = _find(layout, "core-b");
        assert float(core_a["x"]) < LONG_W / 2.0 and float(core_b["x"]) > LONG_W / 2.0;
        assert float(core_b["x"]) - float(layout["launcher_a"][0]) >= 85.0;
        assert float(layout["launcher_b"][0]) - float(core_a["x"]) >= 85.0;
    }
    for layout in _sample()[:6] {
        assert settle_drift(layout) <= 0.12;
    }
}

test "the old scripted flare and lob and the most popular pulls never break a generated core" {
    for layout in _sample()[:10] {
        assert not long_scripted_contact(layout);
        assert not long_scripted_breaks(layout);
    }
    # No single pad pull bursts on the enemy core on more than a quarter of the ridges, for either seat.
    layouts = _sample();
    worst = 0;
    for seat in ["A", "B"] {
        for px in range(0, 401, 20) {
            for py in range(200, 401, 20) {
                aim = release_long(seat, float(px), float(py), 800.0, 400.0, 1.0, True, False, False);
                if not aim.fired {
                    continue;
                }
                hits = 0;
                for layout in layouts {
                    if long_kills(layout, seat, aim.angle, aim.power) {
                        hits = hits + 1;
                    }
                }
                worst = max(worst, hits);
                assert float(hits) / float(len(layouts)) <= 0.25;
            }
        }
    }
    assert worst >= 1;
}

test "a live match on a generated ridge can be won by either seat" {
    for ridge in [3, 41, 919] {
        for winner in ["A", "B"] {
            live = _seated(ridge);
            layout = live.layout;
            # The server secret is random per install, so a ridge may hand over to its deterministic fallback.
            assert int(layout["ridge"]) > 0;
            assert _pull(live, "player-a", "flare-a", _quiet(layout, "A"), "flare")["ok"];
            assert _pull(live, "player-b", "flare-b", _quiet(layout, "B"), "flare")["ok"];
            if winner == "B" {
                assert _pull(live, "player-a", "miss-a", _quiet(layout, "A"), "shell")["ok"];
                finish = _pull(live, "player-b", "core-b", layout["proof"]["B"], "shell");
            } else {
                finish = _pull(live, "player-a", "core-a", layout["proof"]["A"], "shell");
            }
            assert finish["ok"];
            assert finish["result"] == winner;
        }
    }
}

test "the ridge is public but the generated layout stays private" {
    live = _seated(48213);
    layout = live.layout;
    seen = watch(live, "player-b", 0);
    view = json.loads(seen);
    assert view["ridge"] == int(layout["ridge"]) and view["ridge"] > 0;
    assert view["layout_name"] == ridge_name(int(layout["ridge"]));
    assert view["terrain"] == layout["terrain"];
    assert view["field"]["mode"] == "long" and view["field"]["w"] == LONG_W and view["field"]["v_max"] == LONG_V_MAX;
    for leak in ["proof", "exposure", "attempt", "pieces", "layout-test", "core-a", "footing-a"] {
        assert leak not in seen;
    }
    enemy = _find(layout, "core-a");
    assert str(round(float(enemy["x"]), 4)) not in seen;
    mine = [row for row in view["view"]["own"] if row["role"] == "launcher"];
    assert len(mine) == 1;
    assert abs(float(mine[0]["x"]) - float(layout["launcher_b"][0])) < 0.001;
    # Restarting the server keeps the same hidden layout for the same room.
    again = boot_match(live.table.directory, "fogshot");
    assert json.dumps(again.layout, sort_keys=True) == json.dumps(layout, sort_keys=True);
}

test "rematch always rolls a new ridge, and a ridge can be replayed" {
    live = _seated(5);
    finish = _pull(live, "player-a", "flare-a", _quiet(live.layout, "A"), "flare");
    assert finish["ok"];
    _pull(live, "player-b", "flare-b", _quiet(live.layout, "B"), "flare");
    won = _pull(live, "player-a", "core", live.layout["proof"]["A"], "shell");
    assert won["result"] == "A";
    again = json.loads(rematch_room(live, "player-a"));
    assert again["ok"] and again["phase"] == "recon";
    assert again["ridge"] != 5 and again["ridge"] > 0;
    assert live.layout is not None;
    replay = _seated(int(again["ridge"]));
    assert _signature(replay.layout) == _signature(live.layout);
    # A shared ridge may replace an untouched duel, never one already under way.
    shared = json.loads(rematch_room(live, "player-b", 0));
    assert shared["ok"] and shared["ridge"] == 0 and live.layout is None;
    assert _pull(live, "player-a", "flare-x", [20.0, 300.0], "flare")["ok"];
    busy = json.loads(rematch_room(live, "player-b", 48213));
    assert not busy["ok"] and busy["code"] == "active";
    assert json.loads(watch(live, "player-a", 0))["ridge"] == 0;
    classic = _seated(0);
    assert classic.layout is None;
    assert json.loads(watch(classic, "player-a", 0))["ridge"] == 0;
}

def _combat(lx: float) -> str {
    return json.dumps({"seat": "B", "your_turn": True, "phase": "combat", "turn": 5, "epoch": 1,
        "reveal_until": 0, "view": {"own": [{"id": "launcher-b", "role": "launcher", "x": lx, "y": 4.0, "alive": True}],
        "public": [], "reveal": None}});
}

def _spread(streak: int) -> float {
    data = json.loads(_combat(34.0));
    data["reveal_until"] = 100;
    data["view"]["reveal"] = {"bodies": [{"role": "core", "x": 12.5, "y": 2.0, "alive": True}]};
    memory = learn(json.dumps(data), new_memory(1), 1);
    xs: list[float] = [];
    ys: list[float] = [];
    for seed in range(40) {
        plan = json.loads(choose(_combat(34.0), memory, json.dumps({"seed": seed, "streak": streak})));
        assert release_pull("B", float(plan["x"]), float(plan["y"]), 800.0, 400.0, 1.0, True, False, False).fired;
        xs.append(float(plan["x"]));
        ys.append(float(plan["y"]));
    }
    mx = sum(xs) / len(xs);
    my = sum(ys) / len(ys);
    return math.sqrt(sum([(x - mx) * (x - mx) for x in xs]) / len(xs) + sum([(y - my) * (y - my) for y in ys]) / len(ys));
}

test "practice bot is seeded, varies between duels and sharpens with the streak" {
    assert aim_sigma(0, 0) > aim_sigma(1, 0);
    assert aim_sigma(1, 0) > aim_sigma(3, 0);
    assert aim_sigma(3, 0) > aim_sigma(3, 2);
    assert aim_sigma(20, 20) >= 1.0;
    memory = new_memory(1);
    one = choose(_combat(34.0), memory, json.dumps({"seed": 7, "streak": 0}));
    assert one == choose(_combat(34.0), memory, json.dumps({"seed": 7, "streak": 0}));
    assert one != choose(_combat(34.0), memory, json.dumps({"seed": 8, "streak": 0}));
    loose = _spread(0);
    sharp = _spread(4);
    assert loose > 6.0;
    assert sharp < loose * 0.5;
    # The bot aims from wherever this ridge put its launcher.
    moved = json.loads(choose(_combat(33.0), memory, json.dumps({"seed": 7, "streak": 0})));
    assert release_pull("B", float(moved["x"]), float(moved["y"]), 800.0, 400.0, 1.0, True, False, False, 33.0, 4.0).fired;
}

def _long_observation(layout: dict[str, any], reveal: any) -> str {
    spot = layout["launcher_b"];
    return json.dumps({"seat": "B", "your_turn": True, "phase": "combat", "turn": 5, "epoch": 1,
        "reveal_until": 100 if reveal is not None else 0, "field": {"mode": "long", "w": LONG_W, "h": 96.0},
        "terrain": layout["terrain"], "view": {"own": [{"id": "launcher-b", "role": "launcher", "x": spot[0], "y": spot[1], "alive": True}],
        "public": [], "reveal": reveal}});
}

def _long_miss(layout: dict[str, any], memory: str, streak: int) -> float {
    spot = layout["launcher_b"];
    core = _find(layout, "core-a");
    total = 0.0;
    for seed in range(24) {
        plan = json.loads(choose(_long_observation(layout, None), memory, json.dumps({"seed": seed, "streak": streak})));
        aim = release_long("B", float(plan["x"]), float(plan["y"]), 800.0, 400.0, 1.0, True, False, False);
        assert aim.fired and plan["weapon"] == "shell";
        land = free_flight(layout["terrain"], float(spot[0]), float(spot[1]), aim.angle, aim.power);
        total = total + abs(land[1] - float(core["x"]));
    }
    return total / 24.0;
}

test "long-range practice bot solves public ballistics and sharpens with the streak" {
    assert long_sigma(0, 0)[0] > long_sigma(2, 0)[0];
    assert long_sigma(2, 0)[1] > long_sigma(2, 3)[1];
    assert long_sigma(30, 30)[0] >= 0.002;
    layout = _sample()[0];
    core = _find(layout, "core-a");
    seen = {"bodies": [{"role": "core", "x": float(core["x"]), "y": float(core["y"]), "alive": True}]};
    memory = learn(_long_observation(layout, seen), new_memory(1), 1);
    assert "core" in memory;
    loose = _long_miss(layout, memory, 0);
    sharp = _long_miss(layout, memory, 6);
    assert sharp < loose;
    assert sharp < 3.0;
    assert loose > 2.0;
    # Blind, the bot scouts the far band where generated outposts dig in, varying per duel.
    blind = [json.loads(choose(_long_observation(layout, None), new_memory(1), json.dumps({"seed": seed, "streak": 0}))) for seed in range(6)];
    assert len(set([round(float(plan["x"]), 1) for plan in blind])) >= 4;
}
