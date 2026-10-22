"""Procedural outposts. Server-only: the generator, its seeds and every layout stay private.

A public ridge number names a duel. The private layout seed is derived from that
number and a server secret, so the ridge shown in the HUD (and the open-source
generator) cannot be used to rebuild the hidden outpost offline.

Each generated layout is validated before use:
- geometry: in bounds, on its own side, clear of launchers, no overlapping pieces;
- stability: a Pymunk settle pass moves no block or support noticeably;
- reachability: a ballistic sweep of every legal pull finds direct core hits,
  and a real Pymunk proof shot destroys each core;
- fairness: both cores are exposed to a similar share of legal pulls, inside
  bounds that keep the core findable but never trivially exposed.
"""

import json;
import math;
import from game.aim { angle_ok, release_pull }
import from physics.pymunk_driver { PhysicsWorld }

::py::
def _derive(secret, ridge, stream):
    import hashlib
    digest = hashlib.sha256((str(secret) + ":" + str(int(ridge)) + ":" + str(stream)).encode()).hexdigest()
    return int(digest[:12], 16)

def _server_secret(root):
    import os
    import secrets
    from pathlib import Path
    configured = os.environ.get("FOGSHOT_LAYOUT_SECRET", "")
    if configured:
        return configured
    folder = Path(str(root))
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / ".layout-secret"
    if path.exists():
        return path.read_text().strip()
    token = secrets.token_hex(16)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(token)
    os.replace(temporary, path)
    return path.read_text().strip()

def _fresh_ridge():
    import secrets
    return 1 + secrets.randbelow(99999)
::py::

glob TERRAIN_STEP: float = 0.5;
glob SHELL_RADIUS: float = 0.16;
glob EXPOSURE_MIN: float = 0.012;
glob EXPOSURE_MAX: float = 0.09;
glob EXPOSURE_GAP: float = 0.025;
glob SETTLE_STEPS: int = 240;
# Well-known pulls in canvas protocol coordinates (seat B is mirrored by the protocol):
# the old classic flare+lob script's lob and its immediate neighbours. No generated
# core may fall to them, so the memorised classic script cannot win any ridge.
glob SCRIPTED_PULLS: list[list[float]] = [[10.0, 390.0], [0.0, 390.0], [5.0, 396.0]];
glob SCRIPTED_FLARE: list[float] = [20.0, 300.0];
# The most popular direct-hit pulls measured across many generated ridges (flat full-power
# shots). Free flight to the core is refused for these too, to flatten the hit map.
glob POPULAR_PULLS: list[list[float]] = [[0.0, 300.0], [10.0, 320.0]];
glob NAMES: list[str] = ["Ridge", "Hollow", "Saddle", "Spur", "Crest", "Fold", "Scarp", "Barrow"];

# xorshift32 seeded through a splitmix-style scramble: portable, deterministic, no globals.
obj Rng {
    has state: int = 1;

    def next_u32() -> int {
        x = self.state;
        x = x ^ ((x << 13) & 4294967295);
        x = x ^ (x >> 17);
        x = x ^ ((x << 5) & 4294967295);
        self.state = x & 4294967295;
        return self.state;
    }

    def unit() -> float {
        return float(self.next_u32()) / 4294967296.0;
    }

    def uniform(lo: float, hi: float) -> float {
        return lo + (hi - lo) * self.unit();
    }

    def chance(p: float) -> bool {
        return self.unit() < p;
    }

    def pick(lo: int, hi: int) -> int {
        return lo + int(self.unit() * float(hi - lo + 1));
    }

    def sign() -> float {
        return 1.0 if self.unit() < 0.5 else -1.0;
    }

    def gauss() -> float {
        u = max(0.0000001, self.unit());
        v = self.unit();
        return math.sqrt(-2.0 * math.log(u)) * math.cos(2.0 * math.pi * v);
    }
}

def make_rng(seed: int) -> Rng {
    mixed = (seed * 2654435761 + 2246822519) & 4294967295;
    mixed = (mixed ^ (mixed >> 15)) * 2246822519 & 4294967295;
    if mixed == 0 {
        mixed = 1;
    }
    rng = Rng(state=mixed);
    for _ in range(4) {
        rng.next_u32();
    }
    return rng;
}

def layout_seed(secret: str, ridge: int, stream: str) -> int {
    return int(_derive(secret, ridge, stream));
}

def server_secret(folder: str) -> str {
    return str(_server_secret(folder));
}

def fresh_ridge() -> int {
    return int(_fresh_ridge());
}

def ridge_name(ridge: int) -> str {
    if ridge <= 0 {
        return "Classic ridge";
    }
    return NAMES[ridge % len(NAMES)] + " #" + str(ridge);
}

# ---------- terrain (public) ----------

def make_terrain(seed: int) -> list[list[float]] {
    rng = make_rng(seed);
    a1 = rng.uniform(0.15, 0.42);
    f1 = rng.uniform(0.22, 0.42);
    p1 = rng.uniform(0.0, 6.283);
    a2 = rng.uniform(0.04, 0.12);
    f2 = rng.uniform(0.7, 1.2);
    p2 = rng.uniform(0.0, 6.283);
    a3 = rng.uniform(0.01, 0.04);
    f3 = rng.uniform(2.0, 3.0);
    p3 = rng.uniform(0.0, 6.283);
    base = rng.uniform(0.35, 0.7);
    valley = rng.uniform(-0.25, 0.35);
    half: list[float] = [];
    count = int(22.0 / TERRAIN_STEP) + 1;
    for index in range(count) {
        x = -2.0 + float(index) * TERRAIN_STEP;
        # Layered sines, plus a broad cosine bowl or hump toward the shared midline.
        h = base + a1 * math.sin(f1 * x + p1) + a2 * math.sin(f2 * x + p2) + a3 * math.sin(f3 * x + p3);
        h = h - valley * math.pow(max(0.0, 1.0 - abs(20.0 - x) / 6.0), 2.0);
        half.append(min(1.5, max(0.0, h)));
    }
    points: list[list[float]] = [];
    for index in range(count) {
        points.append([-2.0 + float(index) * TERRAIN_STEP, round(half[index], 4)]);
    }
    # Mirror around the midline: the public ground is identical for both seats.
    for index in range(count - 2, -1, -1) {
        points.append([round(40.0 - (-2.0 + float(index) * TERRAIN_STEP), 4), round(half[index], 4)]);
    }
    return points;
}

def ground_at(terrain: list[list[float]], x: float) -> float {
    if len(terrain) == 0 {
        return 0.0;
    }
    if x <= terrain[0][0] {
        return terrain[0][1];
    }
    last = len(terrain) - 1;
    if x >= terrain[last][0] {
        return terrain[last][1];
    }
    # Terrain is sampled on a near-uniform step: jump to the segment, then settle locally.
    step = max(0.0001, (terrain[last][0] - terrain[0][0]) / float(last));
    index = min(last - 1, max(0, int((x - terrain[0][0]) / step)));
    while index > 0 and x < terrain[index][0] {
        index = index - 1;
    }
    while index < last - 1 and x > terrain[index + 1][0] {
        index = index + 1;
    }
    a = terrain[index];
    b = terrain[index + 1];
    span = b[0] - a[0];
    t = 0.0 if span <= 0.0 else (x - a[0]) / span;
    return a[1] + (b[1] - a[1]) * t;
}

def ground_span(terrain: list[list[float]], left: float, right: float, highest: bool) -> float {
    best = ground_at(terrain, left);
    x = left;
    while x <= right {
        h = ground_at(terrain, x);
        best = max(best, h) if highest else min(best, h);
        x = x + 0.1;
    }
    h = ground_at(terrain, right);
    return max(best, h) if highest else min(best, h);
}

# ---------- pieces ----------

def _piece(pid: str, owner: str, role: str, kind: str, x: float, y: float, w: float, h: float, health: float, mass: float = 0.0) -> dict[str, any] {
    return {"id": pid, "owner": owner, "role": role, "kind": kind,
        "x": round(x, 4), "y": round(y, 4), "w": round(w, 4), "h": round(h, 4),
        "angle": 0.0, "health": health, "mass": round(mass, 4)};
}

def _post(pid: str, owner: str, x: float, base_y: float, w: float, h: float, lean: float) -> dict[str, any] {
    clearance = 0.22;
    pivot = base_y + clearance;
    piece = _piece(pid, owner, "post", "post",
        x - math.sin(lean) * (h / 2.0), pivot + math.cos(lean) * (h / 2.0), w, h, 0.5);
    piece["angle"] = round(lean, 4);
    piece["base_x"] = round(x, 4);
    piece["base_y"] = round(base_y, 4);
    piece["clearance"] = clearance;
    return piece;
}

# Axis-aligned bounds of a (possibly rotated) piece: [xmin, xmax, ymin, ymax].
def bounds(piece: dict[str, any]) -> list[float] {
    hw = float(piece["w"]) / 2.0;
    hh = float(piece["h"]) / 2.0;
    a = float(piece["angle"]);
    ex = abs(math.cos(a)) * hw + abs(math.sin(a)) * hh;
    ey = abs(math.sin(a)) * hw + abs(math.cos(a)) * hh;
    x = float(piece["x"]);
    y = float(piece["y"]);
    return [x - ex, x + ex, y - ey, y + ey];
}

def _overlaps(a: list[float], b: list[float], margin: float) -> bool {
    return a[0] < b[1] - margin and b[0] < a[1] - margin and a[2] < b[3] - margin and b[2] < a[3] - margin;
}

def _material(rng: Rng) -> tuple[str, float, float] {
    # (role, density, health): timber shatters on a solid hit, stone takes about two.
    if rng.chance(0.55) {
        return ("timber", 0.7, 0.7);
    }
    return ("stone", 2.2, 2.4);
}

# One outpost for `owner`, attacked from launcher (lx, ly). dir points from that launcher to the outpost.
# Long-range ridges pass dir_sign (+1 / -1), the core band and the zone reach explicitly.
def make_outpost(seed: int, owner: str, terrain: list[list[float]], lx: float, ly: float, dir_sign: float = 0.0, core_lo: float = 3.5, core_hi: float = 6.6, reach_cap: float = -1.0) -> list[dict[str, any]] {
    rng = make_rng(seed);
    dir = 1.0 if owner == "B" else -1.0;
    if dir_sign != 0.0 {
        dir = dir_sign;
    }
    tag = owner.lower();
    reach = abs(20.0 - lx) - 0.7;
    if reach_cap > 0.0 {
        reach = reach_cap;
    }
    pieces: list[dict[str, any]] = [];
    core = rng.uniform(0.6, 0.9);
    width = rng.uniform(1.9, 3.2);
    # Free flight from a launcher tops out near 6.5 m downrange at core height.
    d_core = rng.uniform(core_lo, min(core_hi, reach - 1.1));
    offset = rng.uniform(-0.45, 0.45) * (width / 2.0 - core / 2.0 - 0.1);
    d_found = min(reach - width / 2.0, max(2.9 + width / 2.0, d_core + offset));
    fx = lx + dir * d_found;
    xc = fx - dir * offset;
    left = fx - width / 2.0;
    right = fx + width / 2.0;
    top = ground_span(terrain, left, right, True) + rng.uniform(0.24, 0.62);
    floor = ground_span(terrain, left, right, False) - 0.3;
    pieces.append(_piece("footing-" + tag, owner, "footing", "static", fx, (top + floor) / 2.0, width, top - floor, 99.0));
    lift = rng.uniform(0.0, 1.5);
    seat = top;
    if lift > 0.22 {
        pieces.append(_piece("plinth-" + tag, owner, "plinth", "static", xc, top + lift / 2.0, core * 0.7, lift, 99.0));
        seat = top + lift;
    }
    pieces.append(_piece("core-" + tag, owner, "core", "core", xc, seat + core / 2.0, core, core, 0.4));
    if rng.chance(0.5) {
        mat = _material(rng);
        rw = core + rng.uniform(0.25, 0.7);
        rh = rng.uniform(0.15, 0.26);
        pieces.append(_piece("roof-" + tag, owner, mat[0], "dynamic", xc, seat + core + rh / 2.0, rw, rh, mat[2], rw * rh * mat[1]));
    }
    # Walls and crates stand on the footing, in front of or behind the core.
    walls = rng.pick(1, 3);
    used: list[list[float]] = [[xc - core / 2.0 - 0.05, xc + core / 2.0 + 0.05]];
    for index in range(walls) {
        mat = _material(rng);
        crate = rng.chance(0.4);
        ww = rng.uniform(0.45, 0.7) if crate else rng.uniform(0.22, 0.4);
        wh = ww if crate else rng.uniform(0.6, 1.8);
        front = rng.chance(0.7);
        # The front faces the attacker: back toward the enemy launcher in classic, onward in long range.
        face = -dir if dir_sign == 0.0 else dir;
        side = face if front else -face;
        gap = rng.uniform(0.08, 0.5);
        rim = used[0][0] if side < 0.0 else used[0][1];
        for span in used {
            rim = min(rim, span[0]) if side < 0.0 else max(rim, span[1]);
        }
        wx = rim + side * (gap + ww / 2.0);
        if abs(wx - fx) + ww / 2.0 > width / 2.0 - 0.04 {
            continue;
        }
        used.append([wx - ww / 2.0, wx + ww / 2.0]);
        pieces.append(_piece("wall-" + tag + "-" + str(index), owner, mat[0], "dynamic", wx, top + wh / 2.0, ww, wh, mat[2], ww * wh * mat[1]));
        if crate and rng.chance(0.45) {
            sw = ww * rng.uniform(0.6, 0.95);
            pieces.append(_piece("stack-" + tag + "-" + str(index), owner, mat[0], "dynamic", wx, top + wh + sw / 2.0, sw, sw, mat[2], sw * sw * mat[1]));
        }
    }
    # The supply mast: a braced, hinged support somewhere else in the zone.
    mast_name = "enemy-post" if owner == "B" else "post-a";
    for attempt in range(12) {
        d_mast = rng.uniform(3.0, reach);
        mx = lx + dir * d_mast;
        if mx > left - 0.6 and mx < right + 0.6 {
            continue;
        }
        h = rng.uniform(1.8, 3.2);
        lean = rng.sign() * rng.uniform(0.08, 0.24);
        post = _post(mast_name, owner, mx, ground_at(terrain, mx), rng.uniform(0.14, 0.18), h, lean);
        box = bounds(post);
        if box[0] < left - 0.15 and box[1] > left - 0.15 { continue; }
        if box[0] < right + 0.15 and box[1] > right + 0.15 { continue; }
        if box[0] > left - 0.15 and box[1] < right + 0.15 { continue; }
        pieces.append(post);
        break;
    }
    if rng.chance(0.65) {
        sw = rng.uniform(0.35, 0.6);
        sh = rng.uniform(0.3, 0.5);
        sx = lx + dir * rng.uniform(3.0, reach);
        pieces.append(_piece("spur-" + tag, owner, "spur", "static", sx, ground_at(terrain, sx) + sh / 2.0 - 0.05, sw, sh, 0.05));
    }
    return pieces;
}

# ---------- validation ----------

def geometry_faults(layout: dict[str, any]) -> list[str] {
    faults: list[str] = [];
    pieces = layout["pieces"];
    launchers = [layout["launcher_a"], layout["launcher_b"]];
    terrain = layout["terrain"];
    width = float(layout.get("width", 40.0));
    ceiling = float(layout.get("height", 16.0)) - 4.0;
    mid = width / 2.0;
    roles: list[str] = [];
    for piece in pieces {
        box = bounds(piece);
        owner = str(piece["owner"]);
        roles.append(owner + ":" + str(piece["role"]));
        if box[0] < 0.5 or box[1] > width - 0.5 or box[3] > ceiling {
            faults.append("bounds:" + str(piece["id"]));
        }
        # Classic lobs: each outpost sits in front of the enemy launcher. Long range: in its own half.
        near_a = (owner == "A") == (str(layout.get("mode", "short")) == "long");
        if (near_a and box[1] > mid - 0.3) or (not near_a and box[0] < mid + 0.3) {
            faults.append("side:" + str(piece["id"]));
        }
        for launcher in launchers {
            if abs(float(launcher[0]) - float(piece["x"])) < 2.4 {
                faults.append("launcher:" + str(piece["id"]));
            }
        }
        if str(piece["kind"]) == "post" {
            # Both lower corners clear the ground under them.
            a = float(piece["angle"]);
            hw = float(piece["w"]) / 2.0;
            hh = float(piece["h"]) / 2.0;
            for sx in [-1.0, 1.0] {
                cx = float(piece["x"]) + math.cos(a) * sx * hw + math.sin(a) * hh;
                cy = float(piece["y"]) + math.sin(a) * sx * hw - math.cos(a) * hh;
                if cy < ground_at(terrain, cx) + 0.02 {
                    faults.append("buried:" + str(piece["id"]));
                }
            }
        }
    }
    for owner in ["A", "B"] {
        for need in ["core", "footing", "post"] {
            if (owner + ":" + need) not in roles {
                faults.append("missing:" + owner + ":" + need);
            }
        }
    }
    count = len(pieces);
    for i in range(count) {
        for j in range(i + 1, count) {
            if _overlaps(bounds(pieces[i]), bounds(pieces[j]), 0.01) {
                faults.append("overlap:" + str(pieces[i]["id"]) + "/" + str(pieces[j]["id"]));
            }
        }
    }
    return faults;
}

obj Probe {
    has cx: float;
    has cy: float;
    has hw: float;
    has hh: float;
    has c: float;
    has s: float;
    has box: list[float];
    has id: str;
}

def _probes(pieces: list[dict[str, any]]) -> list[Probe] {
    probes: list[Probe] = [];
    r = SHELL_RADIUS;
    for piece in pieces {
        box = bounds(piece);
        a = float(piece["angle"]);
        probes.append(Probe(cx=float(piece["x"]), cy=float(piece["y"]),
            hw=float(piece["w"]) / 2.0 + r, hh=float(piece["h"]) / 2.0 + r,
            c=math.cos(a), s=math.sin(a),
            box=[box[0] - r, box[1] + r, box[2] - r, box[3] + r], id=str(piece["id"])));
    }
    return probes;
}

# First thing a free-flight shell meets: a piece id, "ground", or "" if it leaves.
# Mirrors Pymunk's semi-implicit Euler with the field's gravity and damping.
def first_contact(x0: float, y0: float, angle: float, power: float, probes: list[Probe], terrain: list[list[float]]) -> str {
    dt = 1.0 / 60.0;
    keep = math.pow(0.85, dt);
    x = x0;
    y = y0;
    vx = math.cos(angle) * power;
    vy = math.sin(angle) * power;
    for step in range(150) {
        vx = vx * keep;
        vy = vy * keep - 9.81 * dt;
        x = x + vx * dt;
        y = y + vy * dt;
        if x < -2.0 or x > 42.0 {
            return "";
        }
        # make_terrain clamps the ground to 1.5 m, so higher shells skip the lookup.
        if y - SHELL_RADIUS <= 1.5 and y - SHELL_RADIUS <= ground_at(terrain, x) {
            return "ground";
        }
        for probe in probes {
            if x < probe.box[0] or x > probe.box[1] or y < probe.box[2] or y > probe.box[3] {
                continue;
            }
            dx = x - probe.cx;
            dy = y - probe.cy;
            lx = dx * probe.c + dy * probe.s;
            ly = -dx * probe.s + dy * probe.c;
            if abs(lx) <= probe.hw and abs(ly) <= probe.hh {
                return probe.id;
            }
        }
    }
    return "";
}

# Every legal pull for `seat` on a 0.35 m pointer grid behind its launcher.
def pull_grid(seat: str, lx: float, ly: float) -> list[list[float]] {
    pulls: list[list[float]] = [];
    step = 0.35;
    wy = 0.0;
    while wy <= min(16.0, ly + 3.0) {
        reach = 0.0;
        while reach < 7.5 {
            wx = lx - reach if seat == "A" else lx + reach;
            if wx >= 0.0 and wx <= 40.0 {
                dx = lx - wx;
                dy = ly - wy;
                power = math.hypot(dx, dy);
                angle = math.atan2(dy, dx);
                if power >= 1.0 and angle_ok(seat, angle) {
                    pulls.append([wx, wy, angle, min(22.0, power)]);
                }
            }
            reach = reach + step;
        }
        wy = wy + step;
    }
    return pulls;
}

# Share of legal pulls whose free flight meets the target core first, and those pulls.
def exposure(layout: dict[str, any], seat: str) -> tuple[float, list[list[float]]] {
    launcher = layout["launcher_a"] if seat == "A" else layout["launcher_b"];
    lx = float(launcher[0]);
    ly = float(launcher[1]);
    target = "core-b" if seat == "A" else "core-a";
    probes = _probes(layout["pieces"]);
    terrain = layout["terrain"];
    pulls = pull_grid(seat, lx, ly);
    hits: list[list[float]] = [];
    for pull in pulls {
        if first_contact(lx, ly, pull[2], pull[3], probes, terrain) == target {
            hits.append(pull);
        }
    }
    if len(pulls) == 0 {
        return (0.0, hits);
    }
    return (float(len(hits)) / float(len(pulls)), hits);
}

def pointer_for(seat: str, wx: float, wy: float) -> list[float] {
    # Canvas protocol coordinates (800 x 400) for a world pointer; seat B is mirrored.
    px = wx * 20.0 if seat == "A" else (40.0 - wx) * 20.0;
    return [round(px, 3), round((1.0 - wy / 16.0) * 400.0, 3)];
}

def build_world(layout: dict[str, any], settle: bool = True) -> PhysicsWorld {
    world = PhysicsWorld();
    world.add_terrain("ground", layout["terrain"]);
    for piece in layout["pieces"] {
        kind = str(piece["kind"]);
        pid = str(piece["id"]);
        if kind == "post" {
            world.add_braced_post(pid, float(piece["base_x"]), float(piece["base_y"]), float(piece["w"]), float(piece["h"]), float(piece["angle"]), float(piece["health"]), float(piece["clearance"]));
        } elif kind == "core" {
            world.add_static_box(pid, float(piece["x"]), float(piece["y"]), float(piece["w"]), float(piece["h"]), float(piece["health"]));
        } elif kind == "static" {
            world.add_fixture(pid, float(piece["x"]), float(piece["y"]), float(piece["w"]), float(piece["h"]), float(piece["health"]), str(piece["role"]));
        } else {
            world.add_box(pid, float(piece["x"]), float(piece["y"]), float(piece["w"]), float(piece["h"]), max(0.05, float(piece["mass"])), float(piece["health"]), str(piece["role"]));
        }
    }
    if settle {
        world.deal_damage = False;
        world.simulate(max_steps=SETTLE_STEPS);
        world.deal_damage = True;
    }
    return world;
}

# Largest drift of any dynamic block or support during a quiet settle.
def settle_drift(layout: dict[str, any]) -> float {
    world = build_world(layout, False);
    world.deal_damage = False;
    world.simulate(max_steps=SETTLE_STEPS);
    worst = 0.0;
    for piece in layout["pieces"] {
        if str(piece["kind"]) not in ["dynamic", "post"] {
            continue;
        }
        track = world.find(str(piece["id"]));
        if track is None {
            return 99.0;
        }
        state = world.read_state(track);
        moved = math.hypot(state.x - float(piece["x"]), state.y - float(piece["y"]));
        turned = abs(state.angle - float(piece["angle"]));
        worst = max(worst, moved, turned);
        if state.broken {
            return 99.0;
        }
    }
    return worst;
}

# A real Pymunk shell from a swept direct-hit pull breaks the core.
def proof_shot(layout: dict[str, any], seat: str, hits: list[list[float]]) -> list[float] {
    if len(hits) == 0 {
        return [];
    }
    mx = 0.0;
    my = 0.0;
    for pull in hits {
        mx = mx + pull[0];
        my = my + pull[1];
    }
    mx = mx / float(len(hits));
    my = my / float(len(hits));
    ordered = sorted(hits, key=lambda (p: list[float]) -> float { return (p[0] - mx) * (p[0] - mx) + (p[1] - my) * (p[1] - my); });
    launcher = layout["launcher_a"] if seat == "A" else layout["launcher_b"];
    target = "core-b" if seat == "A" else "core-a";
    for pull in ordered[:4] {
        world = build_world(layout, True);
        world.add_projectile("shot", float(launcher[0]), float(launcher[1]), pull[3] * math.cos(pull[2]), pull[3] * math.sin(pull[2]), SHELL_RADIUS);
        world.simulate(max_steps=700);
        core = world.find(target);
        if core is not None and core.broken {
            return pointer_for(seat, pull[0], pull[1]);
        }
    }
    return [];
}

def scripted_aims(layout: dict[str, any], seat: str, popular: bool = False) -> list[list[float]] {
    spot = layout["launcher_a"] if seat == "A" else layout["launcher_b"];
    aims: list[list[float]] = [];
    for pull in (SCRIPTED_PULLS + POPULAR_PULLS if popular else SCRIPTED_PULLS) {
        aim = release_pull(seat, pull[0], pull[1], 800.0, 400.0, 1.0, True, False, False, float(spot[0]), float(spot[1]));
        if aim.fired {
            aims.append([aim.angle, aim.power]);
        }
    }
    return aims;
}

# Cheap screen: a scripted pull whose free flight meets the core first.
def scripted_contact(layout: dict[str, any]) -> bool {
    probes = _probes(layout["pieces"]);
    for seat in ["A", "B"] {
        spot = layout["launcher_a"] if seat == "A" else layout["launcher_b"];
        target = "core-b" if seat == "A" else "core-a";
        for aim in scripted_aims(layout, seat, True) {
            if first_contact(float(spot[0]), float(spot[1]), aim[0], aim[1], probes, layout["terrain"]) == target {
                return True;
            }
        }
    }
    return False;
}

# Full Pymunk check (rolling shells, falling roofs, a nudge from the scripted flare first):
# the scripted pulls must leave both cores standing.
def scripted_breaks(layout: dict[str, any]) -> bool {
    for seat in ["A", "B"] {
        spot = layout["launcher_a"] if seat == "A" else layout["launcher_b"];
        target = "core-b" if seat == "A" else "core-a";
        flare = release_pull(seat, SCRIPTED_FLARE[0], SCRIPTED_FLARE[1], 800.0, 400.0, 1.0, True, False, False, float(spot[0]), float(spot[1]));
        for opened in [False, True] {
            for aim in scripted_aims(layout, seat) {
                world = build_world(layout, True);
                if opened and flare.fired {
                    # The classic script's flare can nudge cover before the lob; it does no damage.
                    world.deal_damage = False;
                    world.add_projectile("flare", float(spot[0]), float(spot[1]), flare.power * math.cos(flare.angle), flare.power * math.sin(flare.angle), SHELL_RADIUS);
                    world.simulate(max_steps=1400);
                    world.drop_projectiles();
                    world.deal_damage = True;
                }
                world.add_projectile("shot", float(spot[0]), float(spot[1]), aim[1] * math.cos(aim[0]), aim[1] * math.sin(aim[0]), SHELL_RADIUS);
                world.simulate(max_steps=1400);
                core = world.find(target);
                if core is not None and core.broken {
                    return True;
                }
            }
        }
    }
    return False;
}

def _candidate(ridge: int, secret: str, attempt: int, terrain: list[list[float]], lx: float, ly: float, side_a: int) -> dict[str, any] {
    return {"ridge": ridge, "name": ridge_name(ridge), "classic": False,
        "launcher_a": [lx, ly], "launcher_b": [round(40.0 - lx, 4), ly], "terrain": terrain,
        "pieces": make_outpost(layout_seed(secret, ridge, "b:" + str(attempt)), "B", terrain, lx, ly)
            + make_outpost(layout_seed(secret, ridge, "a:" + str(attempt) + ":" + str(side_a)), "A", terrain, 40.0 - lx, ly)};
}

# Deterministic for (secret, ridge). Returns {} only if no fair layout was found.
def generate(ridge: int, secret: str) -> dict[str, any] {
    terrain_seed = layout_seed(secret, ridge, "terrain");
    terrain = make_terrain(terrain_seed);
    spot = make_rng(layout_seed(secret, ridge, "launch"));
    lx = round(spot.uniform(4.8, 7.2), 3);
    # Flatten a public pad under each launcher; the launcher rides 3.2-5.6 m above it.
    # Moving the launcher changes what every canvas pull does, so pulls cannot be memorised.
    pad = ground_at(terrain, lx);
    for point in terrain {
        if abs(point[0] - lx) <= 1.0 or abs(point[0] - (40.0 - lx)) <= 1.0 {
            point[1] = pad;
        }
    }
    ly = round(pad + spot.uniform(3.2, 5.6), 4);
    for attempt in range(80) {
        side = _candidate(ridge, secret, attempt, terrain, lx, ly, 0);
        only_b = {"launcher_a": side["launcher_a"], "launcher_b": side["launcher_b"], "terrain": terrain,
            "pieces": [p for p in side["pieces"] if str(p["owner"]) == "B"]};
        seen_b = exposure(only_b, "A");
        if seen_b[0] < EXPOSURE_MIN or seen_b[0] > EXPOSURE_MAX {
            continue;
        }
        for side_a in range(10) {
            layout = _candidate(ridge, secret, attempt, terrain, lx, ly, side_a);
            if len(geometry_faults(layout)) > 0 {
                continue;
            }
            seen_a = exposure(layout, "B");
            full_b = exposure(layout, "A");
            if seen_a[0] < EXPOSURE_MIN or seen_a[0] > EXPOSURE_MAX or full_b[0] < EXPOSURE_MIN {
                continue;
            }
            if abs(seen_a[0] - full_b[0]) > EXPOSURE_GAP {
                continue;
            }
            if scripted_contact(layout) {
                continue;
            }
            if settle_drift(layout) > 0.12 {
                continue;
            }
            proof_a = proof_shot(layout, "A", full_b[1]);
            proof_b = proof_shot(layout, "B", seen_a[1]);
            if len(proof_a) == 0 or len(proof_b) == 0 {
                continue;
            }
            if scripted_breaks(layout) {
                continue;
            }
            layout["exposure"] = {"A": round(full_b[0], 4), "B": round(seen_a[0], 4)};
            layout["proof"] = {"A": proof_a, "B": proof_b};
            layout["attempt"] = attempt;
            return layout;
        }
    }
    return {};
}
