"""Allowlist projection. Unrevealed enemy numbers never enter the object that is serialized."""

# Visible rows are dict subclasses so json.dumps(view.__dict__) emits every field
# the caller can also read as an attribute. Enemy health is negative, which means hidden.
::py::
class VisibleBody(dict):
    def __getattr__(self, name):
        try:
            return self[name]
        except KeyError as exc:
            raise AttributeError(name) from exc

class RevealPatch(dict):
    def __getattr__(self, name):
        try:
            return self[name]
        except KeyError as exc:
            raise AttributeError(name) from exc

class PlayerView:
    def __init__(self, own, public, reveal):
        self.own = own
        self.public = public
        self.reveal = reveal

def _visible(body_id, x, y, w, h, angle, role, alive, health):
    return VisibleBody(
        id=body_id,
        x=float(x),
        y=float(y),
        w=float(w),
        h=float(h),
        angle=float(angle),
        role=role,
        alive=bool(alive),
        health=float(health),
    )

def _patch(bodies):
    return RevealPatch(bodies=bodies)

def _player_view(own, public, reveal):
    return PlayerView(own, public, reveal)
::py::

obj SecretBody {
    has id: str;
    has owner: str;
    has x: float;
    has y: float;
    has w: float;
    has h: float;
    has angle: float;
    has role: str;
    has alive: bool;
    has health: float;
}

def _inside(body: SecretBody, cx: float, cy: float, radius: float) -> bool {
    dx = body.x - cx;
    dy = body.y - cy;
    return dx * dx + dy * dy <= radius * radius + 0.0000001;
}

def _clipped(body: SecretBody, cx: float, cy: float, radius: float) -> tuple[float, float] {
    left = cx - radius;
    right = cx + radius;
    bottom = cy - radius;
    top = cy + radius;
    room_w = body.x - left;
    other_w = right - body.x;
    max_half_w = room_w if room_w < other_w else other_w;
    room_h = body.y - bottom;
    other_h = top - body.y;
    max_half_h = room_h if room_h < other_h else other_h;
    if max_half_w < 0.0 {
        max_half_w = 0.0;
    }
    if max_half_h < 0.0 {
        max_half_h = 0.0;
    }
    shown_w = body.w if body.w <= max_half_w * 2.0 else max_half_w * 2.0;
    shown_h = body.h if body.h <= max_half_h * 2.0 else max_half_h * 2.0;
    return (shown_w, shown_h);
}

def project_view(
    seat: str,
    bodies: list[SecretBody],
    cx: float,
    cy: float,
    radius: float,
    opened: bool,
    now_ms: int,
    expiry_ms: int
) -> any {
    friendly: list[any] = [];
    shared: list[any] = [];
    exposed: list[any] = [];
    active = opened and now_ms < expiry_ms;
    for body in bodies {
        if body.role == "marker" {
            continue;
        }
        if body.owner == seat {
            friendly.append(_visible(
                body.id, body.x, body.y, body.w, body.h, body.angle, body.role, body.alive, body.health
            ));
        } elif body.owner == "public" {
            shared.append(_visible(
                body.id, body.x, body.y, body.w, body.h, body.angle, body.role, body.alive, body.health
            ));
        } elif active and _inside(body, cx, cy, radius) {
            span = _clipped(body, cx, cy, radius);
            exposed.append(_visible(
                body.id, body.x, body.y, span[0], span[1], body.angle, body.role, body.alive, -1.0
            ));
        }
    }
    reveal = None;
    if active {
        reveal = _patch(exposed);
    }
    return _player_view(friendly, shared, reveal);
}
