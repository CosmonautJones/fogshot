"""Deterministic practice aim. Input is a copied legal seat observation, never a world."""
import json;
import math;
import from game.aim { release_pull }

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

def _distance(px: float, py: float, tx: float, ty: float) -> float {
    aim = release_pull("B", px, py, 800.0, 400.0, 1.0, True, False, False);
    if not aim.fired {
        return 99999.0;
    }
    # Free-flight guess using public gravity/damping. No collision queries or hidden layout.
    x = 34.0;
    y = 4.0;
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

def choose(observation: str, memory: str) -> str {
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
    slot = (turn // 2) % 6;
    xs = [20.0, 60.0, 95.0, 20.0, 40.0, 80.0];
    ys = [390.0, 300.0, 340.0, 360.0, 380.0, 395.0];
    px = xs[slot];
    py = ys[slot];
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
        for cx in [5.0, 20.0, 40.0, 60.0, 80.0, 100.0] {
            for cy in [300.0, 320.0, 340.0, 360.0, 380.0, 395.0] {
                score = _distance(cx, cy, tx, ty);
                if score < best {
                    best = score;
                    px = cx;
                    py = cy;
                }
            }
        }
        # Stable small aiming errors, not random physics or privileged perfect hits.
        px = max(1.0, min(110.0, px + float((turn + epoch) % 3 - 1) * 3.0));
        py = max(300.0, min(399.0, py + float((turn + 2 * epoch) % 3 - 1) * 5.0));
    }
    weapon = "flare" if phase == "recon" else "shell";
    return json.dumps({"ready": True, "weapon": weapon, "x": px, "y": py});
}
