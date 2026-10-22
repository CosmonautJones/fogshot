"""Long-range artillery ridges: a 124-160 m field, outposts dug in near their own launcher.

Each seat's attack distance (launcher to enemy core) is drawn evenly from 82-124 m (+-2 m); the
launcher gap (100-148 m) and field width (124-160 m) follow, and each hidden outpost sits
12-58 m in front of its own launcher, inside its own half. Shells fly with light drag and burst on
first contact (blast radius LONG_BLAST_R); a core breaks when the burst lands within
about 0.9 m of it. Validation is the same contract as the classic generator, retuned:
a swept angle/power window must be hittable but narrow for both seats, the
scripted flare + lob and the most popular pulls must not break a core, and real
Pymunk proof shots must break each core.
"""
import json;
import math;
import from game.aim {
    LONG_W, LONG_H, LONG_V_MAX, LONG_DRAG, LONG_SHELL_R, LONG_BLAST_R, LONG_BLAST_DMG, LONG_BLAST_PUSH,
    LONG_STEPS, LONG_SETTLE, LONG_PAD_X, LONG_PAD_Y, LONG_FULL_PULL, long_pointer, release_long
}
import from game.layout {
    Rng, make_rng, layout_seed, ridge_name, ground_at, make_outpost, geometry_faults,
    build_world, settle_drift, SCRIPTED_PULLS, SCRIPTED_FLARE, POPULAR_PULLS
}
import from physics.pymunk_driver { PhysicsWorld }

glob LONG_TERRAIN_LEFT: float = -4.0;
glob LONG_MIN_W: float = 124.0;
# Every generated core is at least this far from the enemy launcher.
glob LONG_MIN_ATTACK: float = 82.0;
glob LONG_MAX_ATTACK: float = 124.0;
glob CORE_LO: float = 12.0;
glob CORE_HI: float = 58.0;
glob ZONE_REACH: float = 64.0;
# Share of swept (angle, power) samples near each seat's best line that break the enemy core.
glob LONG_EXPOSURE_MIN: float = 0.05;
glob LONG_EXPOSURE_MAX: float = 0.3;
glob LONG_EXPOSURE_GAP: float = 0.12;
glob SCAN_ANGLES: list[float] = [22.0, 27.0, 32.0, 37.0, 42.0, 47.0, 52.0, 57.0, 62.0, 67.0, 72.0];
glob SCAN_SPAN: float = 0.035;
glob SCAN_SAMPLES: int = 15;

::py::
def _fly(x0, y0, angle, power, probes, heights, left, top, width, coarse, r, drag):
    # Semi-implicit Euler exactly like Pymunk's (dt 1/180, velocity *= drag**dt, then gravity),
    # checked every third step (0.73 m at full speed, under every probe's thickness).
    dt = 1.0 / 180.0
    keep = drag ** dt
    gdt = 9.81 * dt
    vx = math.cos(angle) * power
    vy = math.sin(angle) * power
    x = x0
    y = y0
    n = len(heights) - 1
    stride = 9 if coarse else 3
    zone = probes[0] if probes else None
    for step in range(1, 3601):
        vx = vx * keep
        vy = vy * keep - gdt
        x += vx * dt
        y += vy * dt
        if step % stride:
            continue
        if x < left or x > width - left:
            return ("", x, y)
        low = y - r
        if low <= top:
            fx = x - left
            i = int(fx)
            if i >= n:
                i = n - 1
            g = heights[i] + (heights[i + 1] - heights[i]) * (fx - i)
            if low <= g:
                return ("ground", x, y)
        if zone is not None and zone[0] <= x <= zone[1] and zone[2] <= y <= zone[3]:
            for p in probes[1:]:
                if x < p[6] or x > p[7] or y < p[8] or y > p[9]:
                    continue
                dx = x - p[0]
                dy = y - p[1]
                lx = dx * p[4] + dy * p[5]
                ly = -dx * p[5] + dy * p[4]
                if abs(lx) <= p[2] and abs(ly) <= p[3]:
                    return (p[10], x, y)
    return ("", x, y)

def _probe_rows(pieces, owner, r):
    rows = []
    zx0, zx1, zy0, zy1 = 1e9, -1e9, 1e9, -1e9
    for piece in pieces:
        if owner and str(piece["owner"]) != owner:
            continue
        a = float(piece["angle"])
        hw = float(piece["w"]) / 2.0
        hh = float(piece["h"]) / 2.0
        ex = abs(math.cos(a)) * hw + abs(math.sin(a)) * hh + r
        ey = abs(math.sin(a)) * hw + abs(math.cos(a)) * hh + r
        x = float(piece["x"])
        y = float(piece["y"])
        rows.append((x, y, hw + r, hh + r, math.cos(a), math.sin(a), x - ex, x + ex, y - ey, y + ey, str(piece["id"])))
        zx0, zx1, zy0, zy1 = min(zx0, x - ex), max(zx1, x + ex), min(zy0, y - ey), max(zy1, y + ey)
    return [(zx0, zx1, zy0, zy1)] + rows

def _kills(hit, x, y, core, r, reach):
    # A burst within `reach` of the core surface breaks it (falloff damage >= core health).
    if hit == "" or core is None:
        return False
    if hit == core[4]:
        return True
    gx = max(0.0, abs(x - core[0]) - core[2])
    gy = max(0.0, abs(y - core[1]) - core[3])
    return max(0.0, (gx * gx + gy * gy) ** 0.5 - r) <= reach

def _landing(x0, y0, angle, power, heights, left, top, width, r, drag):
    hit = _fly(x0, y0, angle, power, [], heights, left, top, width, True, r, drag)
    return hit[1]

def _scan(x0, y0, sign, target_x, angles, span, samples, probes, heights, left, top, width, r, drag, vmax, core, reach):
    # For each launch angle, find the power whose terrain-only flight lands at the core,
    # then sweep +-span (fraction of full power) with every hidden piece in the way.
    total = 0
    kills = []
    for degrees in angles:
        pad = math.radians(degrees)
        angle = pad if sign > 0 else math.pi - pad
        lo, hi = 0.2, 1.0
        far = _landing(x0, y0, angle, hi * vmax, heights, left, top, width, r, drag)
        if (far - target_x) * sign < 0:
            total += samples
            continue
        for _ in range(12):
            mid = (lo + hi) / 2.0
            land = _landing(x0, y0, angle, mid * vmax, heights, left, top, width, r, drag)
            if (land - target_x) * sign < 0:
                lo = mid
            else:
                hi = mid
        centre = (lo + hi) / 2.0
        for k in range(samples):
            frac = centre - span + 2.0 * span * k / (samples - 1)
            total += 1
            if frac <= 0.05 or frac > 1.0:
                continue
            hit = _fly(x0, y0, angle, frac * vmax, probes, heights, left, top, width, False, r, drag)
            if _kills(hit[0], hit[1], hit[2], core, r, reach):
                kills.append([angle, frac * vmax])
    return (total, kills)
::py::

def kill_reach() -> float {
    # Distance from the core surface at which a burst still deals the core's 0.4 health.
    return LONG_BLAST_R * (1.0 - 0.4 / LONG_BLAST_DMG);
}

def is_long(layout: any) -> bool {
    return layout is not None and str(layout.get("mode", "short")) == "long";
}

# Public rolling ground across the whole field (default 160 m), mirrored at the midline.
def make_long_terrain(seed: int, width: float = LONG_W) -> list[list[float]] {
    rng = make_rng(seed);
    base = rng.uniform(0.4, 1.2);
    a1 = rng.uniform(0.4, 1.3);
    f1 = rng.uniform(0.07, 0.15);
    p1 = rng.uniform(0.0, 6.283);
    a2 = rng.uniform(0.15, 0.45);
    f2 = rng.uniform(0.28, 0.5);
    p2 = rng.uniform(0.0, 6.283);
    a3 = rng.uniform(0.03, 0.1);
    f3 = rng.uniform(0.9, 1.4);
    p3 = rng.uniform(0.0, 6.283);
    mid = width / 2.0;
    # No man's land: one big central hill, or twin hills around a valley.
    twin = rng.chance(0.45);
    hill_h = rng.uniform(5.0, 11.0) if not twin else rng.uniform(3.5, 8.0);
    hill_w = rng.uniform(7.0, 16.0) if not twin else rng.uniform(4.0, 8.0);
    hill_off = 0.0 if not twin else rng.uniform(10.0, 22.0);
    dip = 0.0 if not twin else rng.uniform(0.0, 0.8);
    side_x = rng.uniform(0.35, 0.75) * mid;
    side_h = rng.uniform(1.0, 4.5);
    side_w = rng.uniform(3.0, 7.0);
    count = int(mid - LONG_TERRAIN_LEFT) + 1;
    half: list[float] = [];
    for index in range(count) {
        x = LONG_TERRAIN_LEFT + float(index);
        h = base + a1 * math.sin(f1 * x + p1) + a2 * math.sin(f2 * x + p2) + a3 * math.sin(f3 * x + p3);
        h = h + hill_h * math.exp(-math.pow((x - (mid - hill_off)) / hill_w, 2.0));
        h = h - dip * math.exp(-math.pow((x - mid) / 4.0, 2.0));
        h = h + side_h * math.exp(-math.pow((x - side_x) / side_w, 2.0));
        half.append(round(min(14.0, max(0.0, h)), 4));
    }
    points: list[list[float]] = [];
    for index in range(count) {
        points.append([LONG_TERRAIN_LEFT + float(index), half[index]]);
    }
    for index in range(count - 2, -1, -1) {
        points.append([width - (LONG_TERRAIN_LEFT + float(index)), half[index]]);
    }
    return points;
}

# Generated long terrain runs from LONG_TERRAIN_LEFT to width - LONG_TERRAIN_LEFT.
def terrain_width(terrain: list[list[float]]) -> float {
    return round(float(terrain[len(terrain) - 1][0]) + float(terrain[0][0]), 4);
}

def terrain_top(terrain: list[list[float]]) -> float {
    top = 0.0;
    for point in terrain {
        top = max(top, float(point[1]));
    }
    return top;
}

def _heights(terrain: list[list[float]]) -> list[float] {
    return [float(point[1]) for point in terrain];
}

def _core(layout: dict[str, any], owner: str) -> any {
    for piece in layout["pieces"] {
        if str(piece["owner"]) == owner and str(piece["role"]) == "core" {
            return (float(piece["x"]), float(piece["y"]), float(piece["w"]) / 2.0, float(piece["h"]) / 2.0, str(piece["id"]));
        }
    }
    return None;
}

# Share of a swept angle/power band around each angle's line that breaks the enemy core,
# and the (angle, power) samples that do. Only the target's pieces block (own cover is behind).
def long_exposure(layout: dict[str, any], seat: str) -> tuple[float, list[list[float]]] {
    launcher = layout["launcher_a"] if seat == "A" else layout["launcher_b"];
    owner = "B" if seat == "A" else "A";
    core = _core(layout, owner);
    if core is None {
        return (0.0, []);
    }
    terrain = layout["terrain"];
    probes = _probe_rows(layout["pieces"], owner, LONG_SHELL_R);
    sign = 1.0 if seat == "A" else -1.0;
    found = _scan(
        float(launcher[0]), float(launcher[1]), sign, float(core[0]), SCAN_ANGLES, SCAN_SPAN, SCAN_SAMPLES,
        probes, _heights(terrain), LONG_TERRAIN_LEFT, terrain_top(terrain), terrain_width(terrain), LONG_SHELL_R, LONG_DRAG,
        LONG_V_MAX, core, kill_reach()
    ) as tuple[int, list[list[float]]];
    if found[0] == 0 {
        return (0.0, found[1]);
    }
    return (float(len(found[1])) / float(found[0]), found[1]);
}

# Free flight of one aim against the whole field: (piece id | "ground" | "", x, y).
def long_contact(layout: dict[str, any], seat: str, angle: float, power: float) -> tuple[str, float, float] {
    launcher = layout["launcher_a"] if seat == "A" else layout["launcher_b"];
    terrain = layout["terrain"];
    probes = _probe_rows(layout["pieces"], "", LONG_SHELL_R);
    return _fly(float(launcher[0]), float(launcher[1]), angle, power, probes, _heights(terrain),
        LONG_TERRAIN_LEFT, terrain_top(terrain), terrain_width(terrain), False, LONG_SHELL_R, LONG_DRAG) as tuple[str, float, float];
}

def long_kills(layout: dict[str, any], seat: str, angle: float, power: float) -> bool {
    hit = long_contact(layout, seat, angle, power);
    core = _core(layout, "B" if seat == "A" else "A");
    return bool(_kills(hit[0], hit[1], hit[2], core, LONG_SHELL_R, kill_reach()));
}

def arm_long(world: PhysicsWorld) -> PhysicsWorld {
    world.blast_radius = LONG_BLAST_R;
    world.blast_damage = LONG_BLAST_DMG;
    world.blast_push = LONG_BLAST_PUSH;
    world.shell_drag = LONG_DRAG;
    world.settle_after = LONG_SETTLE;
    return world;
}

def build_long(layout: dict[str, any], settle: bool = True) -> PhysicsWorld {
    return arm_long(build_world(layout, settle));
}

def fire_long(world: PhysicsWorld, layout: dict[str, any], seat: str, angle: float, power: float, shell: bool) -> None {
    spot = layout["launcher_a"] if seat == "A" else layout["launcher_b"];
    world.drop_projectiles();
    world.deal_damage = shell;
    world.add_projectile("shot", float(spot[0]), float(spot[1]), power * math.cos(angle), power * math.sin(angle), LONG_SHELL_R);
    world.simulate(max_steps=LONG_STEPS);
    world.deal_damage = True;
}

def _broken(world: PhysicsWorld, pid: str) -> bool {
    track = world.find(pid);
    return track is not None and track.broken;
}

# A real Pymunk shell from the middle of the swept window breaks the core.
def long_proof(layout: dict[str, any], seat: str, hits: list[list[float]]) -> list[float] {
    if len(hits) == 0 {
        return [];
    }
    ma = 0.0;
    mp = 0.0;
    for hit in hits {
        ma = ma + hit[0];
        mp = mp + hit[1];
    }
    ma = ma / float(len(hits));
    mp = mp / float(len(hits));
    ordered = sorted(hits, key=lambda (h: list[float]) -> float { return abs(h[0] - ma) * 20.0 + abs(h[1] - mp); });
    target = "core-b" if seat == "A" else "core-a";
    for hit in ordered[:3] {
        pointer = long_pointer(seat, hit[0], hit[1]);
        aim = release_long(seat, pointer[0], pointer[1], 800.0, 400.0, 1.0, True, False, False);
        if not aim.fired {
            continue;
        }
        world = build_long(layout, True);
        fire_long(world, layout, seat, aim.angle, aim.power, True);
        if _broken(world, target) {
            return pointer;
        }
    }
    return [];
}

def long_scripted_aims(seat: str, popular: bool = False) -> list[list[float]] {
    aims: list[list[float]] = [];
    for pull in (SCRIPTED_PULLS + POPULAR_PULLS if popular else SCRIPTED_PULLS) {
        aim = release_long(seat, pull[0], pull[1], 800.0, 400.0, 1.0, True, False, False);
        if aim.fired {
            aims.append([aim.angle, aim.power]);
        }
    }
    return aims;
}

# Every pull past full length is the same full-power shot, so "max power, flat" is the shot a
# player (or script) would memorise. Measured across ridges it was the most popular family,
# so no generated core may be burst by a full-power shot between 10 and 30 degrees.
def long_flat_aims(seat: str) -> list[list[float]] {
    aims: list[list[float]] = [];
    for degrees in range(10, 31) {
        pad = math.radians(float(degrees));
        aims.append([pad if seat == "A" else math.pi - pad, LONG_V_MAX]);
    }
    return aims;
}

# Cheap screen: a scripted, popular or flat full-power pull whose free flight bursts on a core.
def long_scripted_contact(layout: dict[str, any]) -> bool {
    for seat in ["A", "B"] {
        for aim in long_scripted_aims(seat, True) + long_flat_aims(seat) {
            if long_kills(layout, seat, aim[0], aim[1]) {
                return True;
            }
        }
    }
    return False;
}

# Full Pymunk: the scripted lobs, with and without the scripted flare first, leave both cores.
def long_scripted_breaks(layout: dict[str, any]) -> bool {
    for seat in ["A", "B"] {
        target = "core-b" if seat == "A" else "core-a";
        flare = release_long(seat, SCRIPTED_FLARE[0], SCRIPTED_FLARE[1], 800.0, 400.0, 1.0, True, False, False);
        for opened in [False, True] {
            for aim in long_scripted_aims(seat) {
                world = build_long(layout, True);
                if opened and flare.fired {
                    fire_long(world, layout, seat, flare.angle, flare.power, False);
                }
                fire_long(world, layout, seat, aim[0], aim[1], True);
                if _broken(world, target) {
                    return True;
                }
            }
        }
    }
    return False;
}

# Attack distances (launcher to enemy core) are drawn first and evenly in
# [LONG_MIN_ATTACK, LONG_MAX_ATTACK] for each seat; the launcher gap and field width follow.
# Drawing the field first piled most cores up 80-90 m away, which made one remembered pull
# hit about 30% of ridges.
def long_plan(seed: int) -> list[float] {
    rng = make_rng(seed);
    for _ in range(400) {
        da = rng.uniform(LONG_MIN_ATTACK, LONG_MAX_ATTACK);
        db = rng.uniform(LONG_MIN_ATTACK, LONG_MAX_ATTACK);
        # Launcher gaps that keep both cores 12-58 m deep and inside their owner's half.
        low = max(100.0, max(da, db) + CORE_LO);
        high = min(148.0, min(da, db) + CORE_HI, 2.0 * (min(da, db) - 10.0));
        if low > high {
            continue;
        }
        gap = rng.uniform(low, high);
        width = 2.0 * float(round((gap + 2.0 * rng.uniform(6.0, 12.0)) / 2.0));
        lx = round((width - gap) / 2.0, 3);
        if width < LONG_MIN_W or width > LONG_W or lx < 6.0 or lx > 12.0 {
            continue;
        }
        # [width, launcher x, seat A's core depth, seat B's core depth] (depth in front of own launcher)
        return [width, lx, round(gap - db, 3), round(gap - da, 3)];
    }
    return [140.0, 9.0, 30.0, 30.0];
}

def _long_candidate(ridge: int, secret: str, attempt: int, terrain: list[list[float]], lx: float, ly: float, side_a: int, depth_a: float, depth_b: float) -> dict[str, any] {
    width = terrain_width(terrain);
    rx = round(width - lx, 4);
    reach = min(ZONE_REACH, width / 2.0 - lx - 4.0);
    return {"ridge": ridge, "name": ridge_name(ridge), "classic": False, "mode": "long",
        "width": width, "height": LONG_H,
        "launcher_a": [lx, ly], "launcher_b": [rx, ly], "terrain": terrain,
        "pieces": make_outpost(layout_seed(secret, ridge, "long-b:" + str(attempt)), "B", terrain, rx, ly, -1.0, depth_b - 2.0, depth_b + 2.0, reach)
            + make_outpost(layout_seed(secret, ridge, "long-a:" + str(attempt) + ":" + str(side_a)), "A", terrain, lx, ly, 1.0, depth_a - 2.0, depth_a + 2.0, reach)};
}

def _only(layout: dict[str, any], owner: str) -> dict[str, any] {
    return {"launcher_a": layout["launcher_a"], "launcher_b": layout["launcher_b"], "terrain": layout["terrain"],
        "pieces": [p for p in layout["pieces"] if str(p["owner"]) == owner]};
}

# Deterministic for (secret, ridge). Returns {} only if no fair layout was found.
def generate_long(ridge: int, secret: str) -> dict[str, any] {
    for round_no in range(4) {
        tag = "" if round_no == 0 else ":" + str(round_no);
        found = _generate_round(ridge, secret, tag, round_no * 10);
        if len(found) > 0 {
            return found;
        }
    }
    return {};
}

# One field plan (width, launchers, core depths) and ten outpost attempts on it.
def _generate_round(ridge: int, secret: str, tag: str, first: int) -> dict[str, any] {
    plan = long_plan(layout_seed(secret, ridge, "long-plan" + tag));
    width = plan[0];
    lx = plan[1];
    spot = make_rng(layout_seed(secret, ridge, "long-launch" + tag));
    terrain = make_long_terrain(layout_seed(secret, ridge, "long-terrain" + tag), width);
    pad = ground_at(terrain, lx);
    for point in terrain {
        if abs(point[0] - lx) <= 1.5 or abs(point[0] - (width - lx)) <= 1.5 {
            point[1] = pad;
        }
    }
    ly = round(pad + spot.uniform(2.5, 4.0), 4);
    for attempt in range(first, first + 10) {
        side = _long_candidate(ridge, secret, attempt, terrain, lx, ly, 0, plan[2], plan[3]);
        seen_b = long_exposure(_only(side, "B"), "A");
        if seen_b[0] < LONG_EXPOSURE_MIN or seen_b[0] > LONG_EXPOSURE_MAX {
            continue;
        }
        for side_a in range(8) {
            layout = _long_candidate(ridge, secret, attempt, terrain, lx, ly, side_a, plan[2], plan[3]);
            if len(geometry_faults(layout)) > 0 {
                continue;
            }
            seen_a = long_exposure(layout, "B");
            if seen_a[0] < LONG_EXPOSURE_MIN or seen_a[0] > LONG_EXPOSURE_MAX {
                continue;
            }
            if abs(seen_a[0] - seen_b[0]) > LONG_EXPOSURE_GAP {
                continue;
            }
            if long_scripted_contact(layout) {
                continue;
            }
            if settle_drift(layout) > 0.12 {
                continue;
            }
            proof_a = long_proof(layout, "A", seen_b[1]);
            proof_b = long_proof(layout, "B", seen_a[1]);
            if len(proof_a) == 0 or len(proof_b) == 0 {
                continue;
            }
            if long_scripted_breaks(layout) {
                continue;
            }
            layout["exposure"] = {"A": round(seen_b[0], 4), "B": round(seen_a[0], 4)};
            layout["proof"] = {"A": proof_a, "B": proof_b};
            layout["attempt"] = attempt;
            return layout;
        }
    }
    return {};
}

# Public free flight over the public ground only (no hidden pieces): (kind, x, y).
def free_flight(terrain: list[list[float]], x0: float, y0: float, angle: float, power: float) -> tuple[str, float, float] {
    return _fly(x0, y0, angle, power, [], _heights(terrain), float(terrain[0][0]), terrain_top(terrain),
        terrain_width(terrain), False, LONG_SHELL_R, LONG_DRAG) as tuple[str, float, float];
}
