"""World-space pull conversion. The guide is kinematic and does not query collisions."""

import math;

glob ARENA_W: float = 40.0;
glob ARENA_H: float = 16.0;
glob LAUNCH_A: tuple[float, float] = (6.0, 4.0);
glob LAUNCH_B: tuple[float, float] = (34.0, 4.0);
glob MIN_POWER: float = 1.0;
glob MAX_POWER: float = 22.0;
glob MIDLINE: float = 20.0;

obj AimResult {
    has fired: bool;
    has angle: float = 0.0;
    has power: float = 0.0;
    has reason: str = "";
}

def launcher_for(seat: str) -> tuple[float, float] {
    if seat == "B" {
        return LAUNCH_B;
    }
    return LAUNCH_A;
}

def angle_ok(seat: str, angle: float) -> bool {
    if not math.isfinite(angle) {
        return False;
    }
    forward = 1.0 if seat == "A" else -1.0;
    return math.cos(angle) * forward > 0.25 and math.sin(angle) > -0.35;
}

def release_pull(
    seat: str,
    pointer_x: float,
    pointer_y: float,
    canvas_w: float,
    canvas_h: float,
    dpr: float,
    dragging: bool,
    cancelled: bool,
    extra_pointer: bool
) -> AimResult {
    if cancelled {
        return AimResult(fired=False, reason="cancelled");
    }
    if extra_pointer {
        return AimResult(fired=False, reason="duplicate");
    }
    if not dragging {
        return AimResult(fired=False, reason="idle");
    }
    if canvas_w <= 0.0 or canvas_h <= 0.0 or dpr <= 0.0 or not math.isfinite(pointer_x) or not math.isfinite(pointer_y) or not math.isfinite(dpr) {
        return AimResult(fired=False, reason="nonfinite");
    }
    px = pointer_x / dpr;
    py = pointer_y / dpr;
    world_y = (1.0 - (py / canvas_h)) * ARENA_H;
    fraction = px / canvas_w;
    world_x = fraction * ARENA_W if seat == "A" else (1.0 - fraction) * ARENA_W;
    launcher = launcher_for(seat);
    dx = launcher[0] - world_x;
    dy = launcher[1] - world_y;
    power = math.hypot(dx, dy);
    if power < MIN_POWER {
        return AimResult(fired=False, reason="short");
    }
    if power > MAX_POWER {
        power = MAX_POWER;
    }
    angle = math.atan2(dy, dx);
    if not angle_ok(seat, angle) {
        return AimResult(fired=False, reason="angle");
    }
    return AimResult(fired=True, angle=angle, power=power, reason="");
}

def short_guide(seat: str, angle: float, power: float) -> list[tuple[float, float]] {
    origin = launcher_for(seat);
    x = origin[0];
    y = origin[1];
    vx = math.cos(angle) * power;
    vy = math.sin(angle) * power;
    dt = 0.05;
    points: list[tuple[float, float]] = [(x, y)];
    traveled = 0.0;
    while len(points) < 8 and traveled < 4.0 {
        step_x = vx * dt;
        step_y = vy * dt;
        x = x + step_x;
        y = y + step_y;
        vy = vy - 9.81 * dt;
        traveled = traveled + math.hypot(step_x, step_y);
        crossed = (seat == "A" and x >= MIDLINE) or (seat == "B" and x <= MIDLINE);
        if crossed {
            break;
        }
        points.append((x, y));
    }
    return points;
}
