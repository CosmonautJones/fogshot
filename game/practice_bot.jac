"""Practice aim. Input is a copied legal seat observation, never a world.

Decisions are deterministic for (observation, memory, skill). `skill` carries the
bot's private seed and the human's practice win streak: aim error is drawn from
that seed and shrinks as the streak grows and as the bot keeps firing in a duel.
"""
import json;
import math;
import from game.aim { release_pull }
import from game.layout { make_rng }

def new_memory(epoch: int) -> str {
    return json.dumps({"epoch": epoch, "targets": []});
}

def learn(observation: str, memory: str, now_ms: int) -> str {
    data = json.loads(observation);
    epoch = int(data.get("epoch", 1));
    saved = json.loads(memory);
    if int(saved.get("epoch", 0)) != epoch {
        saved = json.loads(new_memory(epoch));
    }
    view = data.get("view", {});
    reveal = view.get("reveal");
    if reveal is None or int(data.get("reveal_until", 0)) <= now_ms {
        return json.dumps(saved);
    }
    targets: list[any] = [];
    for row in saved.get("targets", []) {
        targets.append(row);
    }
    for row in reveal.get("bodies", []) {
        role = str(row.get("role", ""));
        x = float(row.get("x", -1.0));
        y = float(row.get("y", -1.0));
        if role not in ["core", "post", "spur"] or not bool(row.get("alive", False)) {
            continue;
        }
        if not math.isfinite(x) or not math.isfinite(y) or x < 0.0 or x > 40.0 or y < 0.0 or y > 16.0 {
            continue;
        }
        # A coarse remembered point, not an exact silhouette, id, health or live tracker.
        qx = round(x * 4.0) / 4.0;
        qy = round(y * 4.0) / 4.0;
        kept: list[any] = [];
        for old in targets {
            same = str(old["role"]) == role and abs(float(old["x"]) - qx) < 0.75 and abs(float(old["y"]) - qy) < 0.75;
            if not same {
                kept.append(old);
            }
        }
        kept.append({"role": role, "x": qx, "y": qy});
        targets = kept;
    }
    bounded: list[any] = [];
    for index in range(max(0, len(targets) - 8), len(targets)) {
        bounded.append(targets[index]);
    }
    return json.dumps({"epoch": epoch, "targets": bounded});
}

# Error scale in canvas pixels: wide for a new player, tight once they are on a streak,
# and tighter with each further shell in the same duel. Never exactly zero.
def aim_sigma(streak: int, shells_fired: int) -> float {
    return max(1.0, 26.0 * math.pow(0.7, float(max(0, streak))) * math.pow(0.75, float(max(0, shells_fired))));
}

def _launcher(data: any) -> tuple[float, float] {
    view = data.get("view", {}) or {};
    for row in view.get("own", []) or [] {
        if str(row.get("role", "")) == "launcher" {
            return (float(row.get("x", 34.0)), float(row.get("y", 4.0)));
        }
    }
    return (34.0, 4.0);
}

def _distance(px: float, py: float, tx: float, ty: float, lx: float = 34.0, ly: float = 4.0) -> float {
    aim = release_pull("B", px, py, 800.0, 400.0, 1.0, True, False, False, lx, ly);
    if not aim.fired {
        return 99999.0;
    }
    # Free-flight guess using public gravity/damping. No collision queries or hidden layout.
    x = lx;
    y = ly;
    vx = math.cos(aim.angle) * aim.power;
    vy = math.sin(aim.angle) * aim.power;
    best = 99999.0;
    damping = math.pow(0.85, 0.05);
    for step in range(80) {
        x = x + vx * 0.05;
        y = y + vy * 0.05;
        vx = vx * damping;
        vy = (vy - 9.81 * 0.05) * damping;
        if y < -0.5 {
            break;
        }
        distance = (x - tx) * (x - tx) + (y - ty) * (y - ty);
        if distance < best {
            best = distance;
        }
    }
    return best;
}

def choose(observation: str, memory: str, skill: str = "{}") -> str {
    data = json.loads(observation);
    phase = str(data.get("phase", ""));
    if str(data.get("seat", "")) != "B" or not bool(data.get("your_turn", False)) or phase not in ["recon", "combat"] {
        return json.dumps({"ready": False});
    }
    turn = int(data.get("turn", 0));
    epoch = int(data.get("epoch", 1));
    saved = json.loads(memory);
    targets: list[any] = [];
    if int(saved.get("epoch", 0)) == epoch {
        for row in saved.get("targets", []) {
            if str(row.get("role", "")) in ["core", "post", "spur"] {
                targets.append(row);
            }
        }
    }
    profile = json.loads(skill or "{}");
    streak = int(profile.get("streak", 0));
    rng = make_rng(int(profile.get("seed", 0)) * 7919 + epoch * 104729 + turn * 31);
    spot = _launcher(data);
    lx = spot[0];
    ly = spot[1];
    # Pointer range behind this launcher, in seat B's mirrored canvas coordinates.
    back = max(12.0, (40.0 - lx) * 20.0 - 10.0);
    low = min(390.0, max(300.0, (1.0 - ly / 16.0) * 400.0));
    slot = (turn // 2) % 6;
    xs = [20.0, 60.0, 95.0, 20.0, 40.0, 80.0];
    ys = [390.0, 300.0, 340.0, 360.0, 380.0, 395.0];
    # The opening flare follows the pattern; later blind shells wander so no two duels search alike.
    wander = 0.0 if phase == "recon" else 1.0;
    px = min(back, max(2.0, xs[slot] * back / 110.0 + wander * rng.uniform(-8.0, 8.0)));
    py = min(399.0, max(low, low + (ys[slot] - 300.0) * (399.0 - low) / 99.0 + wander * rng.uniform(-6.0, 6.0)));
    target: any = None;
    for row in targets {
        target = row;
        if str(row["role"]) == "core" {
            break;
        }
    }
    if phase == "combat" and target is not None {
        tx = float(target["x"]);
        ty = float(target["y"]);
        best = 99999.0;
        for i in range(12) {
            cx = 2.0 + (back - 2.0) * float(i) / 11.0;
            for j in range(10) {
                cy = low + (399.0 - low) * float(j) / 9.0;
                score = _distance(cx, cy, tx, ty, lx, ly);
                if score < best {
                    best = score;
                    px = cx;
                    py = cy;
                }
            }
        }
        # Seeded human-like aim error. Shells already fired this duel: turns 3, 5, 7...
        sigma = aim_sigma(streak, max(0, (turn - 3) // 2));
        wobble_x = px + rng.gauss() * sigma;
        wobble_y = py + rng.gauss() * sigma * 0.8;
        wobble_x = max(1.0, min(back, wobble_x));
        wobble_y = max(low, min(399.0, wobble_y));
        if release_pull("B", wobble_x, wobble_y, 800.0, 400.0, 1.0, True, False, False, lx, ly).fired {
            px = wobble_x;
            py = wobble_y;
        }
    }
    weapon = "flare" if phase == "recon" else "shell";
    return json.dumps({"ready": True, "weapon": weapon, "x": px, "y": py});
}
