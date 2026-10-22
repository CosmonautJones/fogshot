"""Destructible ground and breakable blocks: deterministic craters, rebuilt collision,
threshold fracture, debris limits, pad protection, reload, privacy and a cost bound."""
import json;
import math;
import tempfile;
import time;
import from physics.pymunk_driver { PhysicsWorld, MAX_DEBRIS }
import from game.aim { LONG_BLAST_R, LONG_BLAST_DMG, LONG_BLAST_PUSH, long_pointer, release_long }
import from game.longrange { LONG_CRATER_R, build_long, generate_long, fire_long }
import from server.live { boot_match, claim_player, take_shot, watch, _craters_for }

glob SECRET: str = "destruction-test-secret";

def _ridge() -> list[list[float]] {
    return [[float(x), round(1.0 + 0.5 * math.sin(float(x) / 7.0), 4)] for x in range(0, 101)];
}

def _gy(x: float) -> float {
    return 1.0 + 0.5 * math.sin(x / 7.0);
}

def _field() -> PhysicsWorld {
    world = PhysicsWorld();
    points = _ridge();
    world.add_terrain("ground", points);
    world.blast_radius = LONG_BLAST_R;
    world.blast_damage = LONG_BLAST_DMG;
    world.blast_push = LONG_BLAST_PUSH;
    world.enable_destruction(points, [10.0, 90.0], LONG_CRATER_R);
    return world;
}

def _get(world: PhysicsWorld, body_id: str) -> any {
    return world.find(body_id) as any;
}

def _y(world: PhysicsWorld, body_id: str) -> float {
    return world.read_state(_get(world, body_id)).y;
}

def _debris(world: PhysicsWorld) -> list[any] {
    return [t for t in world.tracks if t.role == "debris" and not t.broken];
}

# Drop a shell straight down onto (x, ground) so it bursts there.
def _shell_at(world: PhysicsWorld, x: float) -> None {
    world.drop_projectiles();
    world.add_projectile("shot", x, _gy(x) + 2.0, 0.0, -12.0, 0.3);
    world.simulate(max_steps=240);
}

test "the same blasts carve the same ground, and only near the crater" {
    first = _field();
    second = _field();
    before = first.ground_lines();
    for spot in [[40.0, _gy(40.0)], [41.1, _gy(41.1) - 0.4], [63.0, _gy(63.0) + 0.3]] {
        first.carve(spot[0], spot[1], LONG_CRATER_R);
        second.carve(spot[0], spot[1], LONG_CRATER_R);
    }
    after = first.ground_lines();
    assert after == second.ground_lines();
    assert after != before;
    assert len(first.craters()) == 3;
    # Segments far from every crater are untouched.
    far_before = [s for s in before if s[0] < 30.0 or s[0] > 75.0];
    far_after = [s for s in after if s[0] < 30.0 or s[0] > 75.0];
    assert far_before == far_after;
    # The crater floor really is lower: no segment crosses the old surface right above the blast.
    deepest = min([min(s[1], s[3]) for s in after if s[0] >= 39.0 and s[0] <= 41.0]);
    assert deepest < _gy(40.0) - 1.0;
    # Rewinding to the same marks reproduces the same ground on a fresh world.
    third = _field();
    third.rewind_craters(first.craters());
    assert third.ground_lines() == after;
}

test "launcher pads cannot be cratered" {
    world = _field();
    before = world.ground_lines();
    world.carve(10.0, _gy(10.0), LONG_CRATER_R);
    world.carve(90.0, _gy(90.0), LONG_CRATER_R);
    assert world.ground_lines() == before;
}

test "a resting block and a shell fall into a fresh crater" {
    world = _field();
    world.add_box("crate", 50.0, _gy(50.0) + 0.3, 0.6, 0.6, 0.25, 9.0, "timber");
    world.simulate(max_steps=180);
    rest = _y(world, "crate");
    assert abs(rest - (_gy(50.0) + 0.3)) < 0.25;
    # By now the crate is asleep on the ground; the carve has to wake it.
    world.carve(50.0, _gy(50.0), LONG_CRATER_R);
    world.simulate(max_steps=240);
    assert _y(world, "crate") < rest - 0.8;
    # A second shell drops into the hole and stops on the new floor, not the old surface.
    world.drop_projectiles();
    world.deal_damage = False;
    world.add_projectile("probe", 44.0, _gy(44.0) + 2.0, 0.0, 0.0, 0.2);
    world.carve(44.0, _gy(44.0), LONG_CRATER_R);
    world.simulate(max_steps=200);
    assert world.impact_step >= 0;
    assert world.impact_y < _gy(44.0) - 0.8;
    assert world.impact_y > _gy(44.0) - 2.0;
}

test "blocks fracture only past their threshold and stone outlasts timber" {
    world = _field();
    world.add_box("plank", 30.0, _gy(30.0) + 0.6, 0.4, 1.2, 0.34, 0.7, "timber");
    world.add_box("slab", 70.0, _gy(70.0) + 0.6, 0.4, 1.2, 1.06, 2.4, "stone");
    world.simulate(max_steps=60);
    world.hurt("plank", 0.5);
    assert not _get(world, "plank").broken;
    assert len(_debris(world)) == 0;
    # One shell burst at the foot of each block.
    _shell_at(world, 30.5);
    _shell_at(world, 70.5);
    assert _get(world, "plank").broken;
    assert not _get(world, "slab").broken;
    pieces = _debris(world);
    assert len(pieces) == 3;
    assert abs(sum([p.w * p.h for p in pieces]) - 0.4 * 1.2) < 0.001;
    assert all([p.parent == "plank" for p in pieces]);
    # Stone takes more bursts; count its pieces the moment it gives way.
    shells = 1;
    while not _get(world, "slab").broken and shells < 5 {
        _shell_at(world, 70.5);
        shells = shells + 1;
    }
    assert _get(world, "slab").broken and shells >= 2;
    assert len([p for p in _debris(world) if p.parent == "slab"]) == 4;
    # Fragments settle and stop: nothing still flying a few seconds later.
    world.simulate(max_steps=400);
    for piece in _debris(world) {
        state = world.read_state(piece);
        assert abs(state.vx) + abs(state.vy) < 0.3;
        assert state.y > -6.0;
    }
}

test "fragments inherit the velocity of the block they came from" {
    world = _field();
    world.add_box("rail", 50.0, 9.0, 0.3, 1.5, 0.3, 0.7, "timber");
    _get(world, "rail").body.velocity = (4.0, 0.0);
    world.hurt("rail", 1.0);
    for piece in _debris(world) {
        state = world.read_state(piece);
        assert state.vx > 3.0 and state.vx < 5.0;
    }
}

test "fracture is the same every run" {
    shapes: list[str] = [];
    for _ in range(2) {
        world = _field();
        world.add_box("wall", 50.0, _gy(50.0) + 0.75, 0.5, 1.5, 1.6, 2.4, "stone");
        world.simulate(max_steps=30);
        world.hurt("wall", 3.0);
        world.simulate(max_steps=200);
        shapes.append(json.dumps([[p.id, round(p.w, 6), round(p.h, 6), round(world.read_state(p).x, 6), round(world.read_state(p).y, 6)] for p in _debris(world)]));
    }
    assert shapes[0] == shapes[1];
}

test "debris is capped and gentle debris contact does no damage" {
    world = _field();
    for i in range(10) {
        world.add_box("stone-" + str(i), 20.0 + float(i) * 5.0, _gy(20.0 + float(i) * 5.0) + 0.5, 0.5, 1.0, 1.1, 2.4, "stone");
    }
    world.add_static_box("core-x", 80.0, _gy(80.0) + 0.4, 0.8, 0.8, 0.4);
    world.simulate(max_steps=60);
    for i in range(10) {
        world.hurt("stone-" + str(i), 5.0);
    }
    assert len(_debris(world)) <= MAX_DEBRIS;
    assert len(world.debris_specs) == len(_debris(world));
    # A fragment set down on the core does not crush it.
    world.add_debris({"id": "drop~0", "parent": "drop", "material": "timber", "w": 0.3, "h": 0.2, "mass": 0.04});
    _get(world, "drop~0").body.position = (80.0, _gy(80.0) + 1.0);
    world.simulate(max_steps=200);
    assert not _get(world, "core-x").broken;
}

test "craters and debris survive a reload, and craters only reach seats that saw them" {
    room_dir = tempfile.mkdtemp(prefix="fogshot-destruction-");
    live = boot_match(room_dir, "fogshot", 4242);
    claim_player(live, "player-a");
    claim_player(live, "player-b");
    layout = live.layout;
    assert layout["mode"] == "long";
    mid = float(layout["width"]) / 2.0;
    # Recon flares never carve.
    for (player, seat) in [("player-a", "A"), ("player-b", "B")] {
        lob = long_pointer(seat, math.radians(70.0) if seat == "A" else math.pi - math.radians(70.0), 7.0);
        flare = json.loads(take_shot(live, player, "flare-" + seat, lob[0], lob[1], 800.0, 400.0, 1.0,
            live.table.epoch, live.table.turn, live.table.revision, "flare"));
        assert flare["ok"];
    }
    assert len(live.world.craters()) == 0;
    # A lands a lob on its own half: A sees that crater, B must not.
    pointer = long_pointer("A", math.radians(70.0), 7.0);
    result = json.loads(take_shot(live, "player-a", "shell-a", pointer[0], pointer[1], 800.0, 400.0, 1.0,
        live.table.epoch, live.table.turn, live.table.revision, "shell"));
    assert result["ok"];
    marks = live.world.craters();
    assert len(marks) == 1 and marks[0][0] < mid;
    assert len(_craters_for(live, "A")) == 1;
    assert len(_craters_for(live, "B")) == 0;
    seen_b = json.loads(watch(live, "player-b", 0));
    assert "craters" in seen_b and len(seen_b["craters"]) == 0;
    seen_a = json.loads(watch(live, "player-a", 0));
    assert seen_a["craters"] == [[round(m, 3) for m in marks[0]]];
    assert all([len(c) == 3 for c in seen_a["craters"]]);
    # B's lob into its own half is visible to B, not A.
    pointer = long_pointer("B", math.pi - math.radians(70.0), 7.0);
    result = json.loads(take_shot(live, "player-b", "shell-b", pointer[0], pointer[1], 800.0, 400.0, 1.0,
        live.table.epoch, live.table.turn, live.table.revision, "shell"));
    assert result["ok"];
    assert len(_craters_for(live, "B")) == 1 and len(_craters_for(live, "A")) == 1;
    # The hidden layout never shows up through other seat's debris.
    for secret in live.table.secrets {
        if secret.role.startswith("debris") {
            assert secret.owner in ["A", "B"];
        }
    }
    lines = live.world.ground_lines();
    debris = [t.id for t in live.world.tracks if t.role == "debris" and not t.broken];
    again = boot_match(room_dir, "fogshot", 4242);
    assert again.world.ground_lines() == lines;
    assert [t.id for t in again.world.tracks if t.role == "debris" and not t.broken] == debris;
    assert again.crater_seats == live.crater_seats;
}

test "carving and a long shot stay inside the phone budget" {
    world = _field();
    for i in range(24) {
        x = 15.0 + float(i * 37 % 70);
        world.carve(x, _gy(x) - float(i % 3) * 0.3, LONG_CRATER_R);
    }
    worst = max(world.carve_ms);
    mean = sum(world.carve_ms) / float(len(world.carve_ms));
    layout = generate_long(4242, SECRET);
    assert len(layout) > 0;
    # The generator's own proof shot for A: a real kill with fractures, craters and debris.
    live_world = build_long(layout, True);
    pointer = layout["proof"]["A"];
    aim = release_long("A", float(pointer[0]), float(pointer[1]), 800.0, 400.0, 1.0, True, False, False);
    assert aim.fired;
    started = time.perf_counter();
    fire_long(live_world, layout, "A", aim.angle, aim.power, True);
    shot_ms = (time.perf_counter() - started) * 1000.0;
    debris = len([t for t in live_world.tracks if t.role == "debris" and not t.broken]);
    with open("/tmp/fogshot-destruction-perf.json", "w") as out {
        out.write(json.dumps({"carve_mean_ms": round(mean, 2), "carve_worst_ms": round(worst, 2), "shot_ms": round(shot_ms, 1),
            "steps": live_world.step_index, "step_us": round(shot_ms * 1000.0 / max(1, live_world.step_index), 1),
            "crater_count": len(live_world.craters()), "debris": debris, "bodies": len(live_world.space.bodies)}));
    }
    assert mean < 40.0;
    assert worst < 120.0;
    assert shot_ms < 2500.0;
}
