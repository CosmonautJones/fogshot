"""Procedural ridges: deterministic per seed, varied across seeds, always valid, fair and private."""
import json;
import math;
import tempfile;
import from game.aim { release_pull }
import from game.layout { generate, geometry_faults, scripted_contact, scripted_breaks, first_contact, _probes, exposure, settle_drift, ridge_name, make_terrain, ground_at, pointer_for, EXPOSURE_MIN, EXPOSURE_MAX, EXPOSURE_GAP }
import from game.practice_bot { aim_sigma, choose, learn, new_memory }
import from server.live { boot_match, claim_player, rematch_room, take_shot, watch }

glob SECRET: str = "layout-test-secret";
glob SAMPLE: list[dict[str, any]] = [];

glob FALLBACKS: list[int] = [];

# Same deterministic fallback chain as server.live: a ridge with no fair layout hands over to the next.
def _generate(ridge: int) -> dict[str, any] {
    wanted = ridge;
    for attempt in range(6) {
        layout = generate(wanted, SECRET);
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
        for ridge in range(1, 51) {
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
    # A short lob that lands just in front of the shooter's own launcher.
    spot = layout["launcher_a"] if seat == "A" else layout["launcher_b"];
    lx = float(spot[0]);
    back = -1.1 if seat == "A" else 1.1;
    return pointer_for(seat, lx + back, float(spot[1]) - 0.7);
}

def _seated(ridge: int) -> any {
    live = boot_match(tempfile.mkdtemp(prefix="fogshot-ridge-"), "fogshot", ridge);
    assert claim_player(live, "player-a").seat == "A";
    assert claim_player(live, "player-b").seat == "B";
    return live;
}

test "the same ridge and secret always rebuild the same layout" {
    first = generate(48213, SECRET);
    assert len(first) > 0;
    assert json.dumps(first, sort_keys=True) == json.dumps(generate(48213, SECRET), sort_keys=True);
    assert first["name"] == ridge_name(48213);
    assert "#48213" in first["name"];
    # A different server secret gives a different hidden layout for the same public ridge.
    other = generate(48213, "another-server");
    assert _signature(other) != _signature(first);
    assert make_terrain(77) == make_terrain(77);
    assert make_terrain(77) != make_terrain(78);
}

test "fifty ridges give fifty distinct layouts" {
    layouts = _sample();
    assert all([len(layout) > 0 for layout in layouts]);
    signatures = set([_signature(layout) for layout in layouts]);
    assert len(signatures) == 50;
    assert len(set(FALLBACKS)) <= 10;
    cores = set([round(float(_find(layout, "core-b")["x"]), 1) for layout in layouts]);
    launchers = set([float(layout["launcher_a"][0]) for layout in layouts]);
    assert len(cores) >= 15;
    assert len(launchers) >= 20;
    roles = set();
    for layout in layouts {
        for piece in layout["pieces"] {
            roles.add(str(piece["role"]));
        }
    }
    assert "timber" in roles and "stone" in roles;
}

test "every generated layout is valid, stable, reachable and balanced" {
    for layout in _sample() {
        assert geometry_faults(layout) == [];
        rate_a = exposure(layout, "A")[0];
        rate_b = exposure(layout, "B")[0];
        assert rate_a >= EXPOSURE_MIN and rate_a <= EXPOSURE_MAX;
        assert rate_b >= EXPOSURE_MIN and rate_b <= EXPOSURE_MAX;
        assert abs(rate_a - rate_b) <= EXPOSURE_GAP + 0.0001;
        assert len(layout["proof"]["A"]) == 2 and len(layout["proof"]["B"]) == 2;
        # Terrain is mirrored (public); both launchers sit on the same height.
        assert layout["launcher_a"][1] == layout["launcher_b"][1];
        assert abs(ground_at(layout["terrain"], 10.0) - ground_at(layout["terrain"], 30.0)) < 0.0001;
    }
    for layout in _sample()[:6] {
        assert settle_drift(layout) <= 0.12;
    }
}

test "the old scripted lob and the most popular pulls never break a generated core" {
    for layout in _sample()[:12] {
        assert not scripted_contact(layout);
        assert not scripted_breaks(layout);
    }
    # No single canvas pull hits the core first on more than a quarter of the ridges.
    layouts = _sample();
    for px in range(0, 121, 20) {
        for py in range(300, 400, 20) {
            hits = 0;
            for layout in layouts {
                spot = layout["launcher_a"];
                aim = release_pull("A", float(px), float(py), 800.0, 400.0, 1.0, True, False, False, float(spot[0]), float(spot[1]));
                if aim.fired and first_contact(float(spot[0]), float(spot[1]), aim.angle, aim.power, _probes(layout["pieces"]), layout["terrain"]) == "core-b" {
                    hits = hits + 1;
                }
            }
            assert float(hits) / float(len(layouts)) <= 0.25;
        }
    }
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
