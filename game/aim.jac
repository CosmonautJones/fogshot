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
    extra_pointer: bool,
    launcher_x: float = -1.0,
    launcher_y: float = -1.0
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
    if launcher_x >= 0.0 and launcher_y >= 0.0 {
        # Generated ridges move the launcher; the pull is still measured from it.
        launcher = (launcher_x, launcher_y);
    }
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

# ---------- long-range artillery (generated ridges) ----------
# The field is 160 m wide. A pull is measured on a fixed pad in the 800 x 400 protocol
# frame: the client sends PAD - pull, seat B already mirrored, so the same gesture means
# the same shot for both seats. Full pull (LONG_FULL_PULL px) launches at LONG_V_MAX.
glob LONG_W: float = 160.0;
glob LONG_H: float = 96.0;
glob LONG_PAD_X: float = 400.0;
glob LONG_PAD_Y: float = 200.0;
glob LONG_FULL_PULL: float = 240.0;
glob LONG_MIN_PULL: float = 12.0;
glob LONG_V_MAX: float = 44.0;
glob LONG_DRAG: float = 0.97;
glob LONG_SHELL_R: float = 0.3;
glob LONG_BLAST_R: float = 1.5;
glob LONG_BLAST_DMG: float = 1.0;
glob LONG_BLAST_PUSH: float = 1.6;
glob LONG_STEPS: int = 2400;
glob LONG_SETTLE: int = 300;

# Pad pointer (protocol frame, seat-mirrored) for a world angle and speed: the inverse of release_long.
def long_pointer(seat: str, angle: float, power: float) -> list[float] {
    pad_angle = angle if seat == "A" else math.pi - angle;
    span = max(0.0, min(1.0, power / LONG_V_MAX)) * LONG_FULL_PULL;
    return [round(LONG_PAD_X - span * math.cos(pad_angle), 3), round(LONG_PAD_Y + span * math.sin(pad_angle), 3)];
}

def release_long(
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
    px = pointer_x / dpr / canvas_w * 800.0;
    py = pointer_y / dpr / canvas_h * 400.0;
    dx = LONG_PAD_X - px;
    dy = py - LONG_PAD_Y;
    span = math.hypot(dx, dy);
    if span < LONG_MIN_PULL {
        return AimResult(fired=False, reason="short");
    }
    pad_angle = math.atan2(dy, dx);
    angle = pad_angle if seat == "A" else math.pi - pad_angle;
    if not angle_ok(seat, angle) {
        return AimResult(fired=False, reason="angle");
    }
    power = min(1.0, span / LONG_FULL_PULL) * LONG_V_MAX;
    return AimResult(fired=True, angle=angle, power=power, reason="");
}
