"""Trusted Pymunk 7 solver. Jac decides when a brace breaks and reads the result.

Pymunk 7.3.0 exposes collisions through Space.on_collision. Callbacks must not
be treated as the old add_collision_handler API. Joints are removed after the
step that recorded the hit, because that is when the impulse is known.
"""

import math;

# Jac 0.37.23 parses imported Python and rejects pymunk 7.3.0 Body.angle.setter
# (E1030: Type "float" has no attribute "setter"). The solver is still Pymunk.
# This block is the import seam the checker does not walk.
::py::
def _pymunk():
    import pymunk
    return pymunk

def _world_pair(body, local_xy):
    point = body.local_to_world(local_xy)
    return (float(point.x), float(point.y))

def _pose(body):
    return (float(body.position.x), float(body.position.y), float(body.angle))

def _motion(body):
    vel = body.velocity
    return (float(vel.x), float(vel.y), float(body.angular_velocity))

def _place(body, x, y, angle, vx, vy, ang_vel):
    body.position = (float(x), float(y))
    body.angle = float(angle)
    body.velocity = (float(vx), float(vy))
    body.angular_velocity = float(ang_vel)

def _impulse(arbiter):
    imp = arbiter.total_impulse
    return float((imp.x * imp.x + imp.y * imp.y) ** 0.5)

def _contact_point(arbiter):
    points = arbiter.contact_point_set.points
    if not points:
        return (0.0, 0.0, False)
    point = points[0].point_a
    return (float(point.x), float(point.y), True)

def _hits_structure(arbiter):
    for shape in arbiter.shapes:
        if int(shape.collision_type) == 2:
            return True
    return False

def _hits_projectile(arbiter):
    for shape in arbiter.shapes:
        if int(shape.collision_type) == 3:
            return True
    return False

def _drop(space, body, shape, pin):
    if pin is not None:
        space.remove(pin)
    space.remove(body, shape)

def _keep_shape(space, shape):
    if shape not in space.shapes:
        space.add(shape)

def _keep_body(space, body, shape):
    # Shattered blocks leave the space with their body; a restore puts both back.
    if body not in space.bodies:
        space.add(body)
    if shape not in space.shapes:
        space.add(shape)

def _shatter(space, body, shape):
    if shape in space.shapes:
        space.remove(shape)
    if body in space.bodies:
        space.remove(body)

def _terrain(space, points, body_id):
    import pymunk
    made = []
    for index in range(len(points) - 1):
        a = points[index]
        b = points[index + 1]
        segment = pymunk.Segment(space.static_body, (float(a[0]), float(a[1])), (float(b[0]), float(b[1])), 0.05)
        segment.friction = 0.9
        segment.elasticity = 0.0
        segment.collision_type = 1
        segment.fog_id = body_id
        made.append(segment)
    space.add(*made)
    return len(made)

def _dragged(body, keep):
    # Long-range shells ignore space damping (which settles blocks) and keep
    # `keep` of their speed per second instead: light air drag, true gravity.
    import pymunk
    def _velocity(b, gravity, damping, dt):
        pymunk.Body.update_velocity(b, gravity, float(keep) ** dt, dt)
    body.velocity_func = _velocity

def _gap(shape, x, y):
    # Distance from a blast point to a shape's surface; 0 when inside.
    found = shape.point_query((float(x), float(y)))
    return max(0.0, float(found.distance))

def _push(body, x, y, amount):
    pos = body.position
    dx = float(pos.x) - float(x)
    dy = float(pos.y) - float(y)
    span = (dx * dx + dy * dy) ** 0.5
    if span < 1e-6:
        dx, dy, span = 0.0, 1.0, 1.0
    body.apply_impulse_at_world_point((dx / span * amount, dy / span * amount), (float(pos.x), float(pos.y)))

import bisect
import math
import zlib as _zlib

class TerrainMask:
    """Authoritative destructible ground: a signed density grid sampled from the public ridge.

    density = 0.5 + (ground(x) - y) / CELL, then each crater takes min(density, 0.5 + (dist - r) / CELL)
    (signed-distance CSG). march_soft traces the 0.5 iso-line per 4 m chunk into static segments.
    Untouched chunks keep the original polyline segments, so a field with no craters is unchanged.
    """
    CELL = 0.25
    CHUNK = 4.0
    Y0 = -6.0
    Y1 = 16.0
    BEDROCK = -5.0
    PAD = 2.5
    RADIUS = 0.08

    def __init__(self, terrain, pads):
        self.xs = [float(p[0]) for p in terrain]
        self.hs = [float(p[1]) for p in terrain]
        self.x0 = self.xs[0]
        self.x1 = self.xs[-1]
        self.pads = [float(p) for p in pads]
        self.rows = int(round((self.Y1 - self.Y0) / self.CELL)) + 1
        self.cols = int(round((self.x1 - self.x0) / self.CELL)) + 1
        self.per = int(round(self.CHUNK / self.CELL))
        self.chunks = int(math.ceil((self.x1 - self.x0) / self.CHUNK))
        self.columns = {}
        self.craters = []
        self.carved = set()
        self.shapes = {}
        self.original = {}

    def ground(self, x):
        xs, hs = self.xs, self.hs
        if x <= xs[0]:
            return hs[0]
        if x >= xs[-1]:
            return hs[-1]
        i = bisect.bisect_right(xs, x) - 1
        t = (x - xs[i]) / (xs[i + 1] - xs[i])
        return hs[i] + (hs[i + 1] - hs[i]) * t

    def column(self, i):
        col = self.columns.get(i)
        if col is None:
            g = self.ground(self.x0 + i * self.CELL)
            col = [0.5 + (g - (self.Y0 + j * self.CELL)) / self.CELL for j in range(self.rows)]
            self.columns[i] = col
        return col

    def padded(self, x):
        return any(abs(x - p) <= self.PAD for p in self.pads)

    def carve(self, cx, cy, r):
        """Remove a disc; returns the sorted chunk indices whose collision must be rebuilt."""
        # Rounded first, so a rewind from the saved marks rebuilds exactly the same ground.
        cx, cy, r = round(float(cx), 4), round(float(cy), 4), round(float(r), 4)
        self.craters.append((cx, cy, r))
        return self._apply(cx, cy, r)

    def _apply(self, cx, cy, r):
        c = self.CELL
        i0 = max(0, int(math.floor((cx - r - c - self.x0) / c)))
        i1 = min(self.cols - 1, int(math.ceil((cx + r + c - self.x0) / c)))
        j0 = max(0, int(math.floor((max(self.BEDROCK, cy - r - c) - self.Y0) / c)))
        j1 = min(self.rows - 1, int(math.ceil((cy + r + c - self.Y0) / c)))
        touched = set()
        for i in range(i0, i1 + 1):
            x = self.x0 + i * c
            if self.padded(x):
                continue
            col = self.column(i)
            changed = False
            for j in range(j0, j1 + 1):
                y = self.Y0 + j * c
                if y < self.BEDROCK:
                    continue
                d = 0.5 + (math.hypot(x - cx, y - cy) - r) / c
                if d < col[j]:
                    col[j] = d
                    changed = True
            if changed:
                k = min(self.chunks - 1, i // self.per)
                touched.add(k)
                # A sample on a chunk edge belongs to both neighbours.
                if i % self.per == 0 and k > 0:
                    touched.add(k - 1)
        return sorted(touched)

    def sample(self, point):
        x, y = point[0], point[1]
        i = int(round((x - self.x0) / self.CELL))
        j = int(round((y - self.Y0) / self.CELL))
        i = min(self.cols - 1, max(0, i))
        j = min(self.rows - 1, max(0, j))
        return self.column(i)[j]

    def contours(self, k):
        import pymunk
        from pymunk.autogeometry import march_soft, simplify_curves
        a = self.x0 + k * self.CHUNK
        b = min(self.x1, a + self.CHUNK)
        xs = int(round((b - a) / self.CELL)) + 1
        # Only sample up to just above the highest ground in the chunk (craters only lower it).
        top = max(self.ground(a + t * self.CELL) for t in range(xs))
        rows = min(self.rows, int(math.ceil((top + 1.0 - self.Y0) / self.CELL)) + 1)
        y1 = self.Y0 + (rows - 1) * self.CELL
        lines = march_soft(pymunk.BB(a, self.Y0, b, y1), xs, rows, 0.5, self.sample)
        out = []
        for line in lines:
            pts = simplify_curves(line, 0.02)
            if len(pts) >= 2:
                out.append([(round(float(p.x), 5), round(float(p.y), 5)) for p in pts])
        return out


def _mask_new(space, terrain, pads):
    import pymunk
    mask = TerrainMask(terrain, pads)
    for shape in list(space.shapes):
        if isinstance(shape, pymunk.Segment) and shape.body is space.static_body and getattr(shape, "fog_id", "") == "ground":
            mid = (float(shape.a.x) + float(shape.b.x)) / 2.0
            k = min(mask.chunks - 1, max(0, int(math.floor((mid - mask.x0) / mask.CHUNK))))
            mask.original.setdefault(k, []).append(shape)
    return mask

def _segments(space, lines):
    import pymunk
    made = []
    for line in lines:
        for a, b in zip(line, line[1:]):
            seg = pymunk.Segment(space.static_body, a, b, TerrainMask.RADIUS)
            seg.friction = 0.9
            seg.elasticity = 0.0
            seg.collision_type = 1
            seg.fog_id = "ground"
            made.append(seg)
    if made:
        space.add(*made)
    return made

def _mask_rebuild(space, mask, chunks):
    # Swap only the dirty chunks' static segments: original polyline out, marched contour in.
    count = 0
    for k in chunks:
        if k not in mask.carved:
            for seg in mask.original.get(k, []):
                if seg in space.shapes:
                    space.remove(seg)
            mask.carved.add(k)
        old = mask.shapes.get(k, [])
        if old:
            space.remove(*[seg for seg in old if seg in space.shapes])
        mask.shapes[k] = _segments(space, mask.contours(k))
        count += len(mask.shapes[k])
    return count

def _mask_rewind(space, mask, craters):
    # Rebuild the ground from the public ridge plus exactly these craters (rollback / reload).
    before = set(mask.carved)
    mask.columns = {}
    mask.craters = []
    touched = set()
    for c in craters:
        touched.update(mask.carve(c[0], c[1], c[2]))
    for k in sorted(before - touched):
        old = mask.shapes.pop(k, [])
        if old:
            space.remove(*[seg for seg in old if seg in space.shapes])
        for seg in mask.original.get(k, []):
            if seg not in space.shapes:
                space.add(seg)
        mask.carved.discard(k)
    _mask_rebuild(space, mask, sorted(touched))
    return len(touched)

def _mask_craters(mask):
    return [[c[0], c[1], c[2]] for c in mask.craters]

def _mask_lines(mask):
    # Every static ground segment, chunk by chunk (tests / determinism checks).
    out = []
    for k in range(mask.chunks):
        segs = mask.shapes.get(k) if k in mask.carved else mask.original.get(k, [])
        for seg in segs or []:
            out.append((round(float(seg.a.x), 4), round(float(seg.a.y), 4), round(float(seg.b.x), 4), round(float(seg.b.y), 4)))
    return out

def _wake(space, x, y, reach):
    # Bodies near removed ground may be asleep on it; wake them so they fall into the crater.
    import pymunk
    woke = 0
    for body in space.bodies:
        if body.body_type != pymunk.Body.DYNAMIC:
            continue
        p = body.position
        if abs(float(p.x) - x) <= reach and abs(float(p.y) - y) <= reach + 1.0:
            body.activate()
            woke += 1
    return woke

def _seed(text):
    return _zlib.crc32(str(text).encode("utf-8")) & 0xFFFFFFFF

def _score(w, h, count, seed):
    # Pre-scored fracture: cut the longest piece across its long side at 38-62%, repeat.
    state = seed or 1
    def rand():
        nonlocal state
        state = (1103515245 * state + 12345) & 0x7FFFFFFF
        return state / 0x7FFFFFFF
    pieces = [(0.0, 0.0, float(w), float(h))]
    while len(pieces) < count:
        pieces.sort(key=lambda p: -p[2] * p[3])
        ox, oy, pw, ph = pieces.pop(0)
        u = 0.38 + 0.24 * rand()
        if pw >= ph:
            a = pw * u
            pieces.append((ox - pw / 2.0 + a / 2.0, oy, a, ph))
            pieces.append((ox + pw / 2.0 - (pw - a) / 2.0, oy, pw - a, ph))
        else:
            a = ph * u
            pieces.append((ox, oy - ph / 2.0 + a / 2.0, pw, a))
            pieces.append((ox, oy + ph / 2.0 - (ph - a) / 2.0, pw, ph - a))
    pieces.sort(key=lambda p: (round(p[0], 6), round(p[1], 6)))
    return [(round(p[0], 6), round(p[1], 6), round(p[2], 6), round(p[3], 6)) for p in pieces]

def _fragment(space, parent, ox, oy, fw, fh, mass, fog_id):
    # A fragment takes its place in the parent block and the parent's velocity at that point,
    # plus a small outward kick so the pieces separate.
    import pymunk
    pos = parent.local_to_world((ox, oy))
    vel = parent.velocity_at_world_point(pos)
    centre = parent.position
    dx, dy = float(pos.x - centre.x), float(pos.y - centre.y)
    span = (dx * dx + dy * dy) ** 0.5 or 1.0
    body = pymunk.Body(mass, pymunk.moment_for_box(mass, (fw, fh)))
    body.position = pos
    body.angle = parent.angle
    body.velocity = (float(vel.x) + dx / span * 0.6, float(vel.y) + dy / span * 0.6 + 0.4)
    body.angular_velocity = parent.angular_velocity
    shape = pymunk.Poly.create_box(body, (fw, fh))
    shape.friction = 0.8
    shape.elasticity = 0.0
    shape.collision_type = 2
    shape.fog_id = fog_id
    space.add(body, shape)
    return (body, shape)

def _loose_box(space, fog_id, w, h, mass):
    import pymunk
    body = pymunk.Body(mass, pymunk.moment_for_box(mass, (w, h)))
    shape = pymunk.Poly.create_box(body, (w, h))
    shape.friction = 0.8
    shape.elasticity = 0.0
    shape.collision_type = 2
    shape.fog_id = fog_id
    space.add(body, shape)
    return (body, shape)

def _clock():
    import time
    return time.perf_counter()

def _static_box(space, body_id, x, y, w, h):
    import pymunk
    body = pymunk.Body(body_type=pymunk.Body.STATIC)
    body.position = (float(x), float(y))
    shape = pymunk.Poly.create_box(body, (float(w), float(h)))
    shape.friction = 0.3
    shape.elasticity = 0.0
    shape.collision_type = 2
    shape.fog_id = body_id
    space.add(body, shape)
    return (body, shape)
::py::

# Dynamic outpost blocks leave the solver when they break, so later shots pass through.
# In a destructible world (long range) timber and stone first split into debris fragments.
glob SHATTER_ROLES: list[str] = ["timber", "stone", "debris"];
glob FRACTURE_ROLES: list[str] = ["timber", "stone"];
# Fragments per broken block, debris health, and the live debris cap (oldest despawn first).
glob FRAGMENTS: dict[str, int] = {"timber": 3, "stone": 4};
glob DEBRIS_HEALTH: dict[str, float] = {"timber": 0.25, "stone": 0.7};
glob MAX_DEBRIS: int = 24;
glob DEBRIS_KICK: float = 4.0;
# A moving fragment must land at least this impulse on something to hurt it (crush damage).
glob CRUSH_MIN: float = 0.15;

obj BodyState {
    has id: str;
    has x: float;
    has y: float;
    has angle: float;
    has broken: bool = False;
    has alive: bool = True;
    has applications: int = 0;
    has health: float = 0.0;
    has vx: float = 0.0;
    has vy: float = 0.0;
    has ang_vel: float = 0.0;
}

obj SimOutcome {
    has steps: int;
    has pairs: list[str] = [];
    has bodies: list[BodyState] = [];

    def contacted(a: str, b: str) -> bool {
        key = a + "|" + b if a < b else b + "|" + a;
        return key in self.pairs;
    }

    def body(body_id: str) -> BodyState {
        for item in self.bodies {
            if item.id == body_id {
                return item;
            }
        }
        raise ValueError("missing body " + body_id);
    }
}

obj Tracked {
    has id: str;
    has role: str;
    has body: any;
    has shape: any;
    has health: float;
    has broken: bool = False;
    has pin: any = None;
    has kind: str = "dynamic";
    has applications: int = 0;
    has hinged: bool = False;
    has pin_ax: float = 0.0;
    has pin_ay: float = 0.0;
    has pin_bx: float = 0.0;
    has pin_by: float = 0.0;
    has w: float = 0.0;
    has h: float = 0.0;
    has density: float = 0.0;
    has parent: str = "";
    # Step a fragment was made on: the blast that broke its block does not also pulverise it.
    has born: int = -1;
}

def _post_solve(arbiter: any, _space: any, data: any) -> None {
    world = data["world"] as PhysicsWorld;
    world.note(arbiter);
}

obj PhysicsWorld {
    has space: any = None;
    has tracks: list[Tracked] = [];
    has pairs: list[str] = [];
    has damaged: list[str] = [];
    has pending: list[tuple[str, str, float]] = [];
    has dt: float = 1.0 / 180.0;
    has deal_damage: bool = True;
    has trace: list[float] = [];
    has collapse: list[float] = [];
    has collapse_names: list[str] = [];
    has impact_x: float = 0.0;
    has impact_y: float = 0.0;
    has impact_step: int = -1;
    has strike_x: float = 0.0;
    has strike_y: float = 0.0;
    has strike_step: int = -1;
    has step_index: int = 0;
    # Long-range artillery: a shell bursts on first contact (0 radius = classic toss).
    has blast_radius: float = 0.0;
    has blast_damage: float = 0.0;
    has blast_push: float = 0.0;
    has shell_drag: float = 1.0;
    has settle_after: int = 0;
    has blast_step: int = -1;
    has blast_x: float = 0.0;
    has blast_y: float = 0.0;
    # Destruction (long range): carved ground mask, crater radius, debris bookkeeping and costs.
    has mask: any = None;
    has crater_radius: float = 0.0;
    has fracture: bool = False;
    has debris_specs: list[dict[str, any]] = [];
    has carve_ms: list[float] = [];

    def ensure() -> None {
        if self.space is not None {
            return;
        }
        self.space = _pymunk().Space() as any;
        self.space.gravity = (0.0, -9.81);
        self.space.damping = 0.85;
        self.tracks = [];
        self.pairs = [];
        self.damaged = [];
        self.pending = [];
        self.space.on_collision(3, 2, post_solve=_post_solve, data={"world": self});
        self.space.on_collision(3, 1, post_solve=_post_solve, data={"world": self});
        self.space.on_collision(2, 2, post_solve=_post_solve, data={"world": self});
        self.trace = [];
        self.collapse = [];
        self.collapse_names = [];
    }

    def drop_projectiles() -> None {
        self.ensure();
        kept: list[Tracked] = [];
        for track in self.tracks {
            if track.role == "projectile" {
                _drop(self.space, track.body, track.shape, track.pin);
            } else {
                kept.append(track);
            }
        }
        self.tracks = kept;
    }

    def _sample_time() -> float {
        return float(self.step_index + 1) * self.dt;
    }

    def _remember_projectile() -> None {
        elapsed = self._sample_time();
        for track in self.tracks {
            if track.role == "projectile" {
                pose = _pose(track.body) as tuple[float, float, float];
                self.trace.append(pose[0]);
                self.trace.append(pose[1]);
                self.trace.append(elapsed);
            }
        }
    }

    def _remember_posts() -> None {
        elapsed = self._sample_time();
        for track in self.tracks {
            if track.role == "post" {
                pose = _pose(track.body) as tuple[float, float, float];
                self.collapse_names.append(track.id);
                self.collapse.append(pose[2]);
                self.collapse.append(elapsed);
            }
        }
    }

    def add_ground(body_id: str, x1: float, y1: float, x2: float, y2: float) -> None {
        self.ensure();
        segment = _pymunk().Segment(self.space.static_body, (x1, y1), (x2, y2), 0.05) as any;
        segment.friction = 0.9;
        segment.elasticity = 0.0;
        segment.collision_type = 1;
        segment.fog_id = body_id;
        self.space.add(segment);
    }

    def add_terrain(body_id: str, points: list[list[float]]) -> None {
        # A public polyline ridge. Every segment is static ground (collision type 1).
        self.ensure();
        _terrain(self.space, points, body_id);
    }

    def add_box(body_id: str, x: float, y: float, w: float, h: float, mass: float, health: float, role: str, angle: float = 0.0) -> None {
        self.ensure();
        moment = _pymunk().moment_for_box(mass, (w, h));
        body = _pymunk().Body(mass, moment) as any;
        body.position = (x, y);
        body.angle = angle;
        shape = _pymunk().Poly.create_box(body, (w, h)) as any;
        shape.friction = 0.9;
        shape.elasticity = 0.0;
        shape.collision_type = 2;
        shape.fog_id = body_id;
        self.space.add(body, shape);
        self.tracks.append(Tracked(
            id=body_id,
            role=role,
            body=body,
            shape=shape,
            health=health,
            w=w,
            h=h,
            density=mass / max(0.0001, w * h)
        ));
    }

    def add_fixture(body_id: str, x: float, y: float, w: float, h: float, health: float, role: str) -> None {
        self.ensure();
        made = _static_box(self.space, body_id, x, y, w, h) as tuple[any, any];
        self.tracks.append(Tracked(
            id=body_id,
            role=role,
            body=made[0],
            shape=made[1],
            health=health,
            kind="static"
        ));
    }

    def add_static_box(body_id: str, x: float, y: float, w: float, h: float, health: float) -> None {
        self.ensure();
        made = _static_box(self.space, body_id, x, y, w, h) as tuple[any, any];
        self.tracks.append(Tracked(
            id=body_id,
            role="core",
            body=made[0],
            shape=made[1],
            health=health,
            kind="static"
        ));
    }

    def add_projectile(body_id: str, x: float, y: float, vx: float, vy: float, radius: float) -> None {
        self.ensure();
        mass = 0.45;
        moment = _pymunk().moment_for_circle(mass, 0.0, radius);
        body = _pymunk().Body(mass, moment) as any;
        body.position = (x, y);
        body.velocity = (vx, vy);
        shape = _pymunk().Circle(body, radius) as any;
        shape.friction = 0.4;
        shape.elasticity = 0.0;
        shape.collision_type = 3;
        shape.fog_id = body_id;
        self.space.add(body, shape);
        if self.shell_drag < 1.0 {
            _dragged(body, self.shell_drag);
        }
        self.tracks.append(Tracked(
            id=body_id,
            role="projectile",
            body=body,
            shape=shape,
            health=1.0
        ));
    }

    def add_braced_post(body_id: str, x: float, base_y: float, w: float, h: float, lean: float, health: float, clearance: float = 0.35) -> None {
        self.ensure();
        # Keep the pivot clear of the ground segment so the solver cannot jam the hinge.
        pivot_y = base_y + clearance;
        mass = 1.2;
        moment = _pymunk().moment_for_box(mass, (w, h));
        body = _pymunk().Body(mass, moment) as any;
        body.angle = lean;
        body.position = (
            x - math.sin(lean) * (h / 2.0),
            pivot_y + math.cos(lean) * (h / 2.0)
        );
        shape = _pymunk().Poly.create_box(body, (w, h)) as any;
        shape.friction = 0.4;
        shape.elasticity = 0.0;
        shape.collision_type = 2;
        shape.fog_id = body_id;
        self.space.add(body, shape);
        anchor = self.space.static_body;
        top = _world_pair(body, (0.0, h / 2.0)) as tuple[float, float];
        pivot = _pymunk().PivotJoint(anchor, body, _world_pair(body, (0.0, -h / 2.0)));
        pin = _pymunk().PinJoint(anchor, body, top, (0.0, h / 2.0));
        self.space.add(pivot, pin);
        self.tracks.append(Tracked(
            id=body_id,
            role="post",
            body=body,
            shape=shape,
            health=health,
            pin=pin,
            hinged=True,
            pin_ax=top[0],
            pin_ay=top[1],
            pin_bx=0.0,
            pin_by=h / 2.0
        ));
    }

    def _falling(self_a: str, self_b: str) -> bool {
        left = self.find(self_a);
        right = self.find(self_b);
        if left is not None and (left.broken or left.role == "debris") {
            return True;
        }
        if right is not None and (right.broken or right.role == "debris") {
            return True;
        }
        return False;
    }

    def note(arbiter: any) -> None {
        shapes = arbiter.shapes;
        a = str(shapes[0].fog_id);
        b = str(shapes[1].fog_id);
        key = a + "|" + b if a < b else b + "|" + a;
        projectile = _hits_projectile(arbiter) as bool;
        if projectile and (self.impact_step < 0 or self.strike_step < 0) {
            point = _contact_point(arbiter) as tuple[float, float, bool];
            if point[2] and self.impact_step < 0 {
                self.impact_x = point[0];
                self.impact_y = point[1];
                self.impact_step = self.step_index;
            }
            if point[2] and self.strike_step < 0 and _hits_structure(arbiter) as bool {
                self.strike_x = point[0];
                self.strike_y = point[1];
                self.strike_step = self.step_index;
            }
        }
        if key not in self.pairs {
            self.pairs.append(key);
        }
        if key in self.damaged {
            return;
        }
        if not projectile and not self._falling(a, b) {
            return;
        }
        mag = _impulse(arbiter) as float;
        if not projectile and mag < 0.05 {
            return;
        }
        if not projectile and mag < CRUSH_MIN and self._debris_only(a, b) {
            return;
        }
        if not projectile and self._rubble(a, b) {
            # Fragments landing on the ground or on each other just settle; only a blast or
            # a crush against a real block wears them down.
            return;
        }
        self.damaged.append(key);
        self.pending.append((a, b, mag));
    }

    def flush() -> None {
        queued = self.pending;
        self.pending = [];
        for item in queued {
            self.hurt(item[0], item[2]);
            self.hurt(item[1], item[2]);
        }
    }

    def _debris_only(a: str, b: str) -> bool {
        # Neither side is a block already falling apart: only fragments are moving.
        left = self.find(a);
        right = self.find(b);
        if left is not None and left.broken {
            return False;
        }
        if right is not None and right.broken {
            return False;
        }
        return True;
    }

    def _rubble(a: str, b: str) -> bool {
        left = self.find(a);
        right = self.find(b);
        loose_left = left is None or left.role == "debris";
        loose_right = right is None or right.role == "debris";
        return loose_left and loose_right and (left is not None or right is not None);
    }

    def find(body_id: str) -> Tracked | None {
        for track in self.tracks {
            if track.id == body_id {
                return track;
            }
        }
        return None;
    }

    def hurt(body_id: str, amount: float) -> None {
        if not self.deal_damage {
            return;
        }
        track = self.find(body_id);
        if track is None or track.role == "projectile" {
            return;
        }
        track.applications = track.applications + 1;
        track.health = track.health - amount;
        if track.health <= 0.0 and not track.broken {
            if track.pin is not None {
                self.space.remove(track.pin);
                track.pin = None;
            }
            if track.role == "core" {
                self.space.remove(track.shape);
            }
            if self.fracture and track.role in FRACTURE_ROLES {
                self._fracture(track);
            }
            if track.role in SHATTER_ROLES {
                _shatter(self.space, track.body, track.shape);
            }
            track.broken = True;
        }
    }

    # ---- destruction: carved ground (pymunk.autogeometry) and pre-scored block fracture.
    def enable_destruction(terrain: list[list[float]], pads: list[float], crater_radius: float) -> None {
        self.ensure();
        self.mask = _mask_new(self.space, terrain, pads);
        self.crater_radius = crater_radius;
        self.fracture = True;
        self.debris_specs = [];
        self.carve_ms = [];
        # Idle bodies sleep (cheap on phones' worth of debris); carving wakes the ones nearby.
        self.space.sleep_time_threshold = 0.5;
    }

    def carve(x: float, y: float, radius: float) -> int {
        if self.mask is None {
            return 0;
        }
        started = _clock() as float;
        dirty = self.mask.carve(x, y, radius);
        made = _mask_rebuild(self.space, self.mask, dirty) as int;
        _wake(self.space, x, y, radius + 1.5);
        self.carve_ms.append(round(((_clock() as float) - started) * 1000.0, 3));
        return made;
    }

    def craters() -> list[list[float]] {
        if self.mask is None {
            return [];
        }
        return _mask_craters(self.mask) as list[list[float]];
    }

    def rewind_craters(marks: list[list[float]]) -> None {
        if self.mask is None {
            return;
        }
        _mask_rewind(self.space, self.mask, marks);
        _wake(self.space, 0.0, 0.0, 99999.0);
    }

    def ground_lines() -> list[any] {
        if self.mask is None {
            return [];
        }
        return _mask_lines(self.mask) as list[any];
    }

    def _fracture(track: Tracked) -> None {
        material = track.role;
        count = FRAGMENTS.get(material, 3);
        if track.w * track.h < 0.05 {
            count = 2;
        }
        pieces = _score(track.w, track.h, count, _seed(track.id)) as list[tuple[float, float, float, float]];
        index = 0;
        for piece in pieces {
            fid = track.id + "~" + str(index);
            index = index + 1;
            mass = max(0.02, track.density * piece[2] * piece[3]);
            made = _fragment(self.space, track.body, piece[0], piece[1], piece[2], piece[3], mass, fid) as tuple[any, any];
            self.tracks.append(Tracked(id=fid, role="debris", body=made[0], shape=made[1],
                health=DEBRIS_HEALTH.get(material, 0.3), w=piece[2], h=piece[3], density=track.density, parent=track.id, born=self.step_index));
            self.debris_specs.append({"id": fid, "parent": track.id, "material": material, "w": piece[2], "h": piece[3], "mass": mass});
        }
        self._cap_debris();
    }

    def _cap_debris() -> None {
        alive = [t for t in self.tracks if t.role == "debris" and not t.broken];
        extra = len(alive) - MAX_DEBRIS;
        if extra <= 0 {
            return;
        }
        gone: list[str] = [];
        for track in alive[:extra] {
            _shatter(self.space, track.body, track.shape);
            gone.append(track.id);
        }
        self.tracks = [t for t in self.tracks if t.id not in gone];
        self.debris_specs = [d for d in self.debris_specs if str(d["id"]) not in gone];
    }

    # Recreate a saved fragment (reload); restore() then puts it where it was.
    def add_debris(spec: dict[str, any]) -> None {
        self.ensure();
        made = _loose_box(self.space, str(spec["id"]), float(spec["w"]), float(spec["h"]), float(spec["mass"])) as tuple[any, any];
        material = str(spec["material"]);
        self.tracks.append(Tracked(id=str(spec["id"]), role="debris", body=made[0], shape=made[1],
            health=DEBRIS_HEALTH.get(material, 0.3), w=float(spec["w"]), h=float(spec["h"]),
            density=float(spec["mass"]) / max(0.0001, float(spec["w"]) * float(spec["h"])), parent=str(spec["parent"])));
        self.debris_specs.append(spec);
    }

    def debris_material(track: Tracked) -> str {
        for spec in self.debris_specs {
            if str(spec["id"]) == track.id {
                return str(spec["material"]);
            }
        }
        return "timber";
    }

    def read_state(track: Tracked) -> BodyState {
        pose = _pose(track.body) as tuple[float, float, float];
        motion = _motion(track.body) as tuple[float, float, float];
        return BodyState(
            id=track.id,
            x=pose[0],
            y=pose[1],
            angle=pose[2],
            broken=track.broken,
            alive=True,
            applications=track.applications,
            health=track.health,
            vx=motion[0],
            vy=motion[1],
            ang_vel=motion[2]
        );
    }

    def capture() -> list[BodyState] {
        saved: list[BodyState] = [];
        for track in self.tracks {
            saved.append(self.read_state(track));
        }
        return saved;
    }

    def restore(saved: list[BodyState]) -> None {
        self.ensure();
        keep: list[str] = [];
        for item in saved {
            keep.append(item.id);
        }
        removed: list[Tracked] = [];
        for track in self.tracks {
            if track.id not in keep {
                removed.append(track);
            }
        }
        for track in removed {
            _drop(self.space, track.body, track.shape, track.pin);
            track.pin = None;
        }
        kept: list[Tracked] = [];
        for track in self.tracks {
            if track.id in keep {
                kept.append(track);
            }
        }
        self.tracks = kept;
        self.debris_specs = [d for d in self.debris_specs if str(d["id"]) in keep];
        for item in saved {
            track = self.find(item.id);
            if track is None {
                continue;
            }
            _place(track.body, item.x, item.y, item.angle, item.vx, item.vy, item.ang_vel);
            track.health = item.health;
            track.broken = item.broken;
            track.applications = item.applications;
            if item.broken and track.pin is not None {
                self.space.remove(track.pin);
                track.pin = None;
            }
            if track.role == "core" and not item.broken {
                _keep_shape(self.space, track.shape);
            }
            if track.role in SHATTER_ROLES and not item.broken {
                _keep_body(self.space, track.body, track.shape);
            }
            if track.role in SHATTER_ROLES and item.broken {
                # A reload rebuilds every block; a block that had shattered must leave again.
                _shatter(self.space, track.body, track.shape);
            }
            if not item.broken and track.pin is None and track.hinged {
                fresh = _pymunk().PinJoint(
                    self.space.static_body,
                    track.body,
                    (track.pin_ax, track.pin_ay),
                    (track.pin_bx, track.pin_by)
                );
                self.space.add(fresh);
                track.pin = fresh;
            }
        }
    }

    def snapshot(steps: int) -> SimOutcome {
        states: list[BodyState] = [];
        for track in self.tracks {
            states.append(self.read_state(track));
        }
        copied: list[str] = [pair for pair in self.pairs];
        return SimOutcome(steps=steps, pairs=copied, bodies=states);
    }

    def detonate() -> None {
        # First contact: the shell is gone and everything within the blast radius
        # takes falloff damage and a push. Flares (deal_damage off) just stop.
        self.blast_step = self.step_index;
        self.blast_x = self.impact_x;
        self.blast_y = self.impact_y;
        self.drop_projectiles();
        if not self.deal_damage or self.blast_radius <= 0.0 {
            return;
        }
        hits: list[tuple[str, float]] = [];
        for track in self.tracks {
            if track.broken {
                continue;
            }
            gap = _gap(track.shape, self.blast_x, self.blast_y) as float;
            if gap >= self.blast_radius {
                continue;
            }
            share = 1.0 - gap / self.blast_radius;
            if not (track.role == "debris" and track.born == self.step_index) {
                hits.append((track.id, self.blast_damage * share));
            }
            if track.kind == "dynamic" {
                push = self.blast_push * share;
                if track.role == "debris" {
                    # A fragment is light: cap its kick at DEBRIS_KICK m/s so pieces tumble out
                    # of the burst instead of leaving the field.
                    push = min(push, float(track.body.mass) * DEBRIS_KICK);
                }
                _push(track.body, self.blast_x, self.blast_y, push);
            }
        }
        for hit in hits {
            self.hurt(hit[0], hit[1]);
        }
        if self.mask is not None and self.crater_radius > 0.0 {
            self.carve(self.blast_x, self.blast_y, self.crater_radius);
        }
    }

    def simulate(max_steps: int = 600) -> SimOutcome {
        self.ensure();
        self.pairs = [];
        self.damaged = [];
        self.pending = [];
        self.trace = [];
        self.collapse = [];
        self.collapse_names = [];
        self.impact_step = -1;
        self.impact_x = 0.0;
        self.impact_y = 0.0;
        self.strike_step = -1;
        self.strike_x = 0.0;
        self.strike_y = 0.0;
        self.blast_step = -1;
        self.blast_x = 0.0;
        self.blast_y = 0.0;
        steps = 0;
        while steps < max_steps {
            self.step_index = steps;
            self.space.step(self.dt);
            steps = steps + 1;
            self.flush();
            if self.blast_radius > 0.0 and self.impact_step >= 0 and self.blast_step < 0 {
                self._remember_projectile();
                self.detonate();
            }
            if self.blast_step >= 0 and self.settle_after > 0 and steps - self.blast_step > self.settle_after {
                break;
            }
            if steps % 20 == 0 {
                self._remember_projectile();
                self._remember_posts();
            }
        }
        return self.snapshot(steps);
    }
}
