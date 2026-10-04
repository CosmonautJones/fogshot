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

def _drop(space, body, shape, pin):
    if pin is not None:
        space.remove(pin)
    space.remove(body, shape)

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
        self.trace = [];
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

    def _remember_projectile() -> None {
        for track in self.tracks {
            if track.role == "projectile" {
                pose = _pose(track.body) as tuple[float, float, float];
                self.trace.append(pose[0]);
                self.trace.append(pose[1]);
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

    def add_box(body_id: str, x: float, y: float, w: float, h: float, mass: float, health: float, role: str) -> None {
        self.ensure();
        moment = _pymunk().moment_for_box(mass, (w, h));
        body = _pymunk().Body(mass, moment) as any;
        body.position = (x, y);
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
            health=health
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

    def note(arbiter: any) -> None {
        shapes = arbiter.shapes;
        a = str(shapes[0].fog_id);
        b = str(shapes[1].fog_id);
        key = a + "|" + b if a < b else b + "|" + a;
        if key not in self.pairs {
            self.pairs.append(key);
        }
        if key in self.damaged {
            return;
        }
        mag = _impulse(arbiter) as float;
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
            track.broken = True;
        }
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

    def simulate(max_steps: int = 600) -> SimOutcome {
        self.ensure();
        self.pairs = [];
        self.damaged = [];
        self.pending = [];
        self.trace = [];
        steps = 0;
        while steps < max_steps {
            self.space.step(self.dt);
            steps = steps + 1;
            self.flush();
            if steps % 20 == 0 {
                self._remember_projectile();
            }
        }
        return self.snapshot(steps);
    }
}
