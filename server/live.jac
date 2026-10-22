"""One match per private room. A canvas pull becomes the Pymunk shot, and the wire is an allowlist."""

import json;
import math;
import from pathlib { Path }
import from game.aim { launcher_for, release_pull, release_long, LONG_W, LONG_H, LONG_PAD_X, LONG_PAD_Y, LONG_FULL_PULL, LONG_MIN_PULL, LONG_V_MAX, LONG_DRAG, LONG_SHELL_R, LONG_BLAST_R, LONG_STEPS }
import from game.layout { build_world, fresh_ridge, generate, ridge_name, server_secret }
import from game.longrange { build_long, generate_long, is_long }
import from game.practice_bot { choose, learn, new_memory }
import from game.rules { MatchRules, accept_shot, copy_rules, resolve_cores }
import from graph.supply { Cable, Site, assess }
import from physics.pymunk_driver { BodyState, PhysicsWorld, SimOutcome }
import from server.authority { ClaimResult, Table, append_commit, claim, note_seen, release_player, release_stale, reload_table, save_seats, submit }
import from server.clock { server_now }
import from server.views { SecretBody, project_view }

::py::
def _room_root():
    import os
    return os.environ.get("FOGSHOT_ROOM_ROOT", "/tmp/fogshot-rooms")

import threading
_room_guard = threading.RLock()
_room_locks = {}

def _room_lock(key):
    with _room_guard:
        return _room_locks.setdefault(str(key), threading.RLock())

def _practice_code(owner, attempt):
    import hashlib
    return hashlib.sha256(("practice:" + str(owner) + ":" + str(attempt)).encode()).hexdigest()[:6]

def _publish_practice(directory, owner, invite, builder, ridge=0):
    import os
    import tempfile
    from pathlib import Path
    parent = Path(directory).parent
    parent.mkdir(parents=True, exist_ok=True)
    # A code-shaped directory becomes visible only after durable initialization.
    with tempfile.TemporaryDirectory(prefix=".practice-", dir=parent) as staging:
        live = builder(staging, owner, invite, ridge)
        os.rename(staging, directory)
        live.table.directory = directory
        return live

def _same_shot(payload, seat, weapon, angle, power, epoch):
    parts = str(payload).split("|")
    if len(parts) < 6:
        return False
    if parts[0] != seat or parts[3] != weapon:
        return False
    stored_epoch = int(parts[6]) if len(parts) > 6 else 1
    if stored_epoch != int(epoch):
        return False
    return abs(float(parts[4]) - float(angle)) < 1e-9 and abs(float(parts[5]) - float(power)) < 1e-9

def _shot_parts(payload):
    parts = str(payload).split("|")
    if len(parts) < 6:
        return ("", "", 0.0, 0.0, False)
    return (parts[0], parts[3], float(parts[4]), float(parts[5]), True)

def _raise_if(flag):
    if flag:
        raise OSError("interrupted")

def _pop_last(items):
    if len(items):
        items.pop()

def _replace_file(path, text, fail):
    if fail:
        raise OSError("storage")
    import os
    from pathlib import Path
    temporary = str(path) + ".tmp"
    Path(temporary).write_text(str(text))
    os.replace(temporary, str(path))

def _read_file(path):
    from pathlib import Path
    file = Path(str(path))
    if not file.exists():
        return ""
    return file.read_text()

def _fresh_code():
    import secrets
    return secrets.token_hex(3)

def _code_ok(code):
    text = str(code or "")
    if len(text) != 6:
        return False
    for ch in text:
        if ch not in "0123456789abcdef":
            return False
    return True

def _room_store():
    store = getattr(_room_store, "rooms", None)
    if store is None:
        store = {}
        _room_store.rooms = store
    return store

def _remember_room(code, live):
    _room_store()[str(code)] = live

def _recall_room(code):
    return _room_store().get(str(code))

# A small in-memory pool of ready fresh ridges, refilled by one background thread, so
# room creation and Rematch rarely wait on generation. Never persisted or exposed.
_ridge_pool = []
_ridge_pool_lock = threading.Lock()
_ridge_pool_busy = [False]

def _pool_take():
    with _ridge_pool_lock:
        return _ridge_pool.pop(0) if _ridge_pool else None

def _pool_refill(make, size):
    with _ridge_pool_lock:
        if _ridge_pool_busy[0] or len(_ridge_pool) >= size:
            return
        _ridge_pool_busy[0] = True
    def run():
        try:
            for _ in range(size * 2):
                with _ridge_pool_lock:
                    if len(_ridge_pool) >= size:
                        break
                layout = make()
                if layout:
                    with _ridge_pool_lock:
                        _ridge_pool.append(layout)
        except Exception:
            pass
        finally:
            with _ridge_pool_lock:
                _ridge_pool_busy[0] = False
    threading.Thread(target=run, name="fogshot-ridge-pool", daemon=True).start()

::py::

obj LiveMatch {
    has table: Table;
    has world: PhysicsWorld;
    has reveal_seat: str = "";
    has reveal_until: int = 0;
    has reveal_x: float = 0.0;
    has reveal_y: float = 0.0;
    has reveal_radius: float = 4.0;
    has source_a: any = None;
    has mast_a: any = None;
    has core_node_a: any = None;
    has source_b: any = None;
    has mast_b: any = None;
    has core_node_b: any = None;
    has core_a_alive: bool = True;
    has core_b_alive: bool = True;
    has refused: bool = False;
    has practice: any = None;
    has shot_path: list[list[float]] = [];
    has shot_collapse: list[list[float]] = [];
    has shot_collapse_id: str = "";
    # None is the hand-tuned classic ridge (fixtures and legacy rooms); otherwise a generated layout.
    has layout: any = None;
}

glob _shared: LiveMatch | None = None;
glob ROOM_ROOT: str = _room_root() as str;

def _chain(owner: str, source_name: str, mast_name: str, core_name: str) -> tuple[Site, Site, Site] {
    source = Site(name=source_name, owner=owner, kind="source", intact=True);
    mast = Site(name=mast_name, owner=owner, kind="link", intact=True);
    core = Site(name=core_name, owner=owner, kind="objective", intact=True);
    source +>:Cable():+> mast;
    mast +>:Cable():+> core;
    return (source, mast, core);
}

def _launcher(live: LiveMatch, seat: str) -> tuple[float, float] {
    if live.layout is None {
        return launcher_for(seat);
    }
    spot = live.layout["launcher_b"] if seat == "B" else live.layout["launcher_a"];
    return (float(spot[0]), float(spot[1]));
}

def _ridge(live: LiveMatch) -> int {
    return 0 if live.layout is None else int(live.layout["ridge"]);
}

def _public_terrain(live: LiveMatch) -> list[list[float]] {
    if live.layout is None {
        return [[-2.0, 0.0], [42.0, 0.0]];
    }
    return live.layout["terrain"];
}

def _long(live: LiveMatch) -> bool {
    return is_long(live.layout);
}

def _field_width(live: LiveMatch) -> float {
    return float(live.layout.get("width", LONG_W)) if _long(live) else 40.0;
}

# Public field facts the client needs to scale, aim and preview; nothing hidden.
def _field(live: LiveMatch) -> dict[str, any] {
    if not _long(live) {
        return {"mode": "classic", "w": 40.0, "h": 16.0};
    }
    return {"mode": "long", "w": _field_width(live), "h": LONG_H, "pad_x": LONG_PAD_X, "pad_y": LONG_PAD_Y,
        "full_pull": LONG_FULL_PULL, "min_pull": LONG_MIN_PULL, "v_max": LONG_V_MAX,
        "gravity": 9.81, "drag": LONG_DRAG, "shell": LONG_SHELL_R, "blast": LONG_BLAST_R};
}

def _arm_generated(live: LiveMatch) -> None {
    layout = live.layout;
    live.world = build_long(layout, True) if is_long(layout) else build_world(layout, True);
    live.core_a_alive = True;
    live.core_b_alive = True;
    la = _launcher(live, "A");
    lb = _launcher(live, "B");
    secrets: list[SecretBody] = [
        SecretBody(id="launcher-a", owner="A", x=la[0], y=la[1], w=0.4, h=0.4, angle=0.0, role="launcher", alive=True, health=1.0),
        SecretBody(id="launcher-b", owner="B", x=lb[0], y=lb[1], w=0.4, h=0.4, angle=0.0, role="launcher", alive=True, health=1.0),
        SecretBody(id="far-a", owner="A", x=87654.32, y=1.0, w=0.2, h=0.2, angle=0.0, role="marker", alive=True, health=1.0)
    ];
    for piece in layout["pieces"] {
        secrets.append(SecretBody(
            id=str(piece["id"]), owner=str(piece["owner"]), x=float(piece["x"]), y=float(piece["y"]),
            w=float(piece["w"]), h=float(piece["h"]), angle=float(piece["angle"]), role=str(piece["role"]),
            alive=True, health=float(piece["health"])
        ));
    }
    secrets.append(SecretBody(id="sentinel", owner="hidden", x=12345.67, y=-9876.54, w=1.0, h=1.0, angle=0.2, role="objective", alive=True, health=9.0));
    span = _field_width(live);
    secrets.append(SecretBody(id="ground", owner="public", x=span / 2.0, y=0.0, w=span + 4.0, h=0.1, angle=0.0, role="ground", alive=True, health=1.0));
    live.table.secrets = secrets;
    _sync_post(live);
}

def _layout_path(directory: str) -> str {
    return directory + "/layout.json";
}

# The canonical snapshot carries its own layout, so a snapshot and its world always agree.
def _stored_layout(directory: str) -> any {
    canonical = _read_file(_canonical_path(directory)) as str;
    if canonical != "" {
        try {
            data = json.loads(canonical);
            if "layout" in data {
                return data["layout"];
            }
        } except Exception {
            canonical = "";
        }
    }
    raw = _read_file(_layout_path(directory)) as str;
    if raw == "" {
        return None;
    }
    return json.loads(raw)["layout"];
}

def _write_layout(directory: str, layout: any) -> None {
    _replace_file(_layout_path(directory), json.dumps({"version": 1, "layout": layout}), False);
}

def _generate_ridge(ridge: int) -> any {
    secret = server_secret(ROOM_ROOT);
    wanted = ridge if ridge > 0 else fresh_ridge();
    for attempt in range(6) {
        # Every generated ridge is a long-range artillery field; ridge 0 stays the classic lob.
        layout = generate_long(wanted, secret);
        if len(layout) > 0 {
            return layout;
        }
        # Deterministic fallback so a shared ridge link always lands on the same duel.
        wanted = (wanted * 7919 + 13) % 99999 + 1;
    }
    return None;
}

def _fresh_layout() -> any {
    return _generate_ridge(-1);
}

# ridge: -1 fresh random, 0 classic fixture, N > 0 that public ridge on this server.
def make_layout(ridge: int) -> any {
    if ridge == 0 {
        return None;
    }
    if ridge > 0 {
        return _generate_ridge(ridge);
    }
    layout = _pool_take();
    if layout is None {
        layout = _fresh_layout();
    }
    _pool_refill(_fresh_layout, 2);
    return layout;
}

def _arm(live: LiveMatch) -> None {
    if live.layout is not None {
        _arm_generated(live);
        return;
    }
    world = PhysicsWorld();
    world.add_ground("ground", -2.0, 0.0, 42.0, 0.0);
    # Pointer (20, 300) on an 800 by 400 canvas is angle 0 at power 5.
    # That shell breaks the braced mast. The static core at (11.2, 2.6)
    # sits above that roll and stays alive until the higher shell.
    # The siege fixture (x=20, health 4, angle 0.15, power 14) is unchanged.
    # Clearance 0.22 keeps a flat shell on the post. The 0.35 siege pivot
    # lets a fraction of a degree slip underneath that thin brace.
    world.add_braced_post("enemy-post", 21.0, 0.0, 0.14, 3.2, 0.22, 0.5, 0.22);
    # A's mast sits on B's approach, past the valley post, so B's flat shell can
    # reach it and A's shell, which stops on the valley post, does not.
    world.add_braced_post("post-a", 26.0, 0.0, 0.16, 2.0, -0.15, 0.5, 0.22);
    world.add_fixture("spur-b", 18.45, 1.55, 0.5, 0.45, 0.05, "spur");
    world.add_static_box("core-b", 11.2, 2.6, 0.8, 0.8, 0.4);
    # B's pull-back ends at the arena edge, so a shell stops on the mast near x=26.
    # A's core sits on that approach, at 30.61, where the lob (20, 390) arrives.
    world.add_static_box("core-a", 30.61, 4.05, 0.8, 0.8, 0.4);
    live.world = world;
    live.core_a_alive = True;
    live.core_b_alive = True;
    live.table.secrets = [
        SecretBody(
            id="launcher-a", owner="A", x=6.0, y=4.0, w=0.4, h=0.4,
            angle=0.0, role="launcher", alive=True, health=1.0
        ),
        SecretBody(
            id="core-a", owner="A", x=30.61, y=4.05, w=0.8, h=0.8,
            angle=0.0, role="core", alive=True, health=0.4
        ),
        SecretBody(
            id="far-a", owner="A", x=87654.32, y=1.0, w=0.2, h=0.2,
            angle=0.0, role="marker", alive=True, health=1.0
        ),
        SecretBody(
            id="launcher-b", owner="B", x=34.0, y=4.0, w=0.4, h=0.4,
            angle=0.0, role="launcher", alive=True, health=1.0
        ),
        SecretBody(
            id="core-b", owner="B", x=11.2, y=2.6, w=0.8, h=0.8,
            angle=0.0, role="core", alive=True, health=0.4
        ),
        SecretBody(
            id="enemy-post", owner="B", x=21.0, y=2.0, w=0.14, h=3.2,
            angle=0.22, role="post", alive=True, health=0.5
        ),
        SecretBody(
            id="post-a", owner="A", x=26.0, y=1.2, w=0.16, h=2.0,
            angle=-0.15, role="post", alive=True, health=0.5
        ),
        SecretBody(
            id="spur-b", owner="B", x=18.45, y=1.55, w=0.5, h=0.45,
            angle=0.0, role="spur", alive=True, health=0.05
        ),
        SecretBody(
            id="sentinel", owner="hidden", x=12345.67, y=-9876.54, w=1.0, h=1.0,
            angle=0.2, role="objective", alive=True, health=9.0
        ),
        SecretBody(
            id="ground", owner="public", x=20.0, y=0.0, w=44.0, h=0.1,
            angle=0.0, role="ground", alive=True, health=1.0
        )
    ];
    _sync_post(live);
}

def boot_match(directory: str, invite: str = "fogshot", ridge: int = 0) -> LiveMatch {
    Path(directory).mkdir(parents=True, exist_ok=True);
    stored = _stored_layout(directory);
    if stored is None and ridge != 0 {
        stored = make_layout(ridge);
        if stored is not None {
            _write_layout(directory, stored);
        }
    }
    table = reload_table(invite, directory);
    live = LiveMatch(table=table, world=PhysicsWorld(), layout=stored);
    side_a = _chain("A", "launcher-a", "mast-a", "core-a");
    side_b = _chain("B", "launcher-b", "mast-b", "core-b");
    live.source_a = side_a[0];
    live.mast_a = side_a[1];
    live.core_node_a = side_a[2];
    live.source_b = side_b[0];
    live.mast_b = side_b[1];
    live.core_node_b = side_b[2];
    _arm(live);
    if not _load_canonical(live) {
        _replay(live);
    }
    return live;
}

def _canonical_path(directory: str) -> str {
    return directory + "/canonical.json";
}

def _refresh_cores(live: LiveMatch) -> None {
    core_a = live.world.find("core-a");
    core_b = live.world.find("core-b");
    if core_a is not None {
        live.core_a_alive = not core_a.broken;
    }
    if core_b is not None {
        live.core_b_alive = not core_b.broken;
    }
}

def _save_canonical(live: LiveMatch, fail: bool) -> None {
    bodies: list[any] = [];
    for item in live.world.capture() {
        bodies.append({
            "id": item.id,
            "x": item.x,
            "y": item.y,
            "angle": item.angle,
            "broken": item.broken,
            "health": item.health,
            "applications": item.applications,
            "vx": item.vx,
            "vy": item.vy,
            "ang_vel": item.ang_vel
        });
    }
    intact_a = True;
    intact_b = True;
    if live.mast_a is not None {
        intact_a = (live.mast_a as Site).intact;
    }
    if live.mast_b is not None {
        intact_b = (live.mast_b as Site).intact;
    }
    text = json.dumps({
        "version": 1,
        "practice": live.practice,
        "solver": "pymunk-7.3.0",
        "epoch": live.table.epoch,
        "shots": live.table.shots,
        "turn": live.table.turn,
        "revision": live.table.revision,
        "phase": live.table.rules.phase,
        "active": live.table.rules.active,
        "result": live.table.rules.result,
        "flare_a": live.table.rules.flare_a,
        "flare_b": live.table.rules.flare_b,
        "commits": live.table.commits,
        "payloads": live.table.payloads,
        "reveal_seat": live.reveal_seat,
        "reveal_until": live.reveal_until,
        "reveal_x": live.reveal_x,
        "reveal_y": live.reveal_y,
        "reveal_radius": live.reveal_radius,
        "mast_a": intact_a,
        "mast_b": intact_b,
        "shot_path": live.shot_path,
        "shot_collapse": live.shot_collapse,
        "shot_collapse_id": live.shot_collapse_id,
        "bodies": bodies,
        "layout": live.layout
    });
    _replace_file(_canonical_path(live.table.directory), text, fail);
}

def _load_canonical(live: LiveMatch) -> bool {
    raw = _read_file(_canonical_path(live.table.directory)) as str;
    if raw == "" {
        return False;
    }
    data = json.loads(raw);
    if int(data["version"]) != 1 or str(data["solver"]) != "pymunk-7.3.0" {
        live.refused = True;
        return True;
    }
    live.practice = data.get("practice");
    if live.practice is not None {
        live.table.seat_a = str(live.practice["owner"]);
        live.table.seat_b = str(live.practice["bot"]);
    }
    live.table.epoch = int(data["epoch"]);
    live.table.shots = int(data["shots"]);
    live.table.turn = int(data["turn"]);
    live.table.revision = int(data["revision"]);
    live.table.rules = MatchRules(
        phase=str(data["phase"]),
        turn=int(data["turn"]),
        revision=int(data["revision"]),
        active=str(data["active"]),
        result=str(data["result"]),
        flare_a=bool(data["flare_a"]),
        flare_b=bool(data["flare_b"])
    );
    live.table.commits = [];
    live.table.payloads = [];
    for item in data["commits"] {
        live.table.commits.append(str(item));
    }
    for item in data["payloads"] {
        live.table.payloads.append(str(item));
    }
    saved: list[BodyState] = [];
    for row in data["bodies"] {
        saved.append(BodyState(
            id=str(row["id"]),
            x=float(row["x"]),
            y=float(row["y"]),
            angle=float(row["angle"]),
            broken=bool(row["broken"]),
            health=float(row["health"]),
            applications=int(row["applications"]),
            vx=float(row["vx"]),
            vy=float(row["vy"]),
            ang_vel=float(row["ang_vel"])
        ));
    }
    live.world.restore(saved);
    _sync_post(live);
    _refresh_cores(live);
    if live.mast_a is not None {
        mast = live.mast_a as Site;
        mast.intact = bool(data["mast_a"]);
    }
    if live.mast_b is not None {
        mast_b = live.mast_b as Site;
        mast_b.intact = bool(data["mast_b"]);
    }
    live.reveal_seat = str(data["reveal_seat"]);
    live.reveal_until = int(data["reveal_until"]);
    live.reveal_x = float(data["reveal_x"]);
    live.reveal_y = float(data["reveal_y"]);
    live.reveal_radius = float(data["reveal_radius"]);
    live.shot_path = [];
    live.shot_collapse = [];
    live.shot_collapse_id = "";
    try {
        live.shot_collapse_id = str(data["shot_collapse_id"]);
        for point in data["shot_path"] {
            live.shot_path.append([float(point[0]), float(point[1]), float(point[2])]);
        }
        for sample in data["shot_collapse"] {
            live.shot_collapse.append([float(sample[0]), float(sample[1])]);
        }
    } except Exception {
        live.shot_path = [];
        live.shot_collapse = [];
        live.shot_collapse_id = "";
    }
    return True;
}

def shared_match() -> LiveMatch {
    if _shared is None {
        _shared = boot_match(".fogshot-match");
    }
    return _shared as LiveMatch;
}

def open_room(ridge: int = -1) -> str {
    with _room_lock("__create__") {
        attempt = 0;
        while attempt < 8 {
            code = str(_fresh_code() as str);
            with _room_lock(code) {
                if not (_code_ok(code) as bool) or Path(ROOM_ROOT + "/" + code).exists() {
                    attempt = attempt + 1;
                    continue;
                }
                live = boot_match(ROOM_ROOT + "/" + code, code, ridge);
                _remember_room(code, live);
                return code;
            }
        }
        return "";
    }
}

def room_match(code: str) -> any {
    with _room_lock(code if (_code_ok(code) as bool) else "__invalid__") {
        if not (_code_ok(code) as bool) {
            return None;
        }
        found = _recall_room(code);
        if found is not None {
            return found;
        }
        directory = ROOM_ROOT + "/" + code;
        if not Path(directory).exists() {
            return None;
        }
        live = boot_match(directory, code);
        _remember_room(code, live);
        return live;
    }
}

def _match_for(invite: str) -> any {
    return room_match(invite);
}

def claim_player(live: LiveMatch, player_id: str) -> ClaimResult {
    if live.practice is not None and str(live.practice["owner"]) != player_id {
        return ClaimResult(ok=False, code="unauthenticated");
    }
    return claim(live.table, player_id, live.table.invite);
}

def _seat(live: LiveMatch, player_id: str) -> str {
    if player_id != "" and player_id == live.table.seat_a {
        return "A";
    }
    if player_id != "" and player_id == live.table.seat_b {
        return "B";
    }
    return "";
}

def _sync_post(live: LiveMatch) -> None {
    for secret in live.table.secrets {
        body_id = secret.id;
        if secret.role in ["launcher", "marker", "ground", "objective"] {
            continue;
        }
        track = live.world.find(body_id);
        if track is None {
            continue;
        }
        state = live.world.read_state(track);
        for body in live.table.secrets {
            if body.id == body_id {
                body.x = state.x;
                body.y = state.y;
                body.angle = state.angle;
                body.health = state.health;
                body.alive = not state.broken;
            }
        }
    }
}

def _powered(live: LiveMatch, seat: str) -> bool {
    if seat == "A" and live.source_a is not None and live.core_node_a is not None {
        status = assess(live.source_a as Site, [live.core_node_a as Site]);
        return "core-a" in status.powered;
    }
    if seat == "B" and live.source_b is not None and live.core_node_b is not None {
        status = assess(live.source_b as Site, [live.core_node_b as Site]);
        return "core-b" in status.powered;
    }
    return False;
}

def _enemy_cores(live: LiveMatch, seat: str) -> int {
    if seat == "A" {
        return 1 if live.core_b_alive else 0;
    }
    if seat == "B" {
        return 1 if live.core_a_alive else 0;
    }
    return 0;
}

def _own_core(live: LiveMatch, seat: str) -> bool {
    if seat == "A" {
        return live.core_a_alive;
    }
    if seat == "B" {
        return live.core_b_alive;
    }
    return False;
}

def _ready(live: LiveMatch) -> bool {
    return live.table.rules.phase != "finished" and live.table.rules.result == "";
}

def _apply_hit(live: LiveMatch, outcome: SimOutcome, weapon: str) -> None {
    _sync_post(live);
    post = live.world.find("enemy-post");
    if post is not None and post.broken and live.mast_b is not None {
        mast = live.mast_b as Site;
        mast.intact = False;
    }
    post_a = live.world.find("post-a");
    if post_a is not None and post_a.broken and live.mast_a is not None {
        mast_a = live.mast_a as Site;
        mast_a.intact = False;
    }
    core_a = live.world.find("core-a");
    if core_a is not None {
        live.core_a_alive = not core_a.broken;
    }
    core_b = live.world.find("core-b");
    if core_b is not None {
        live.core_b_alive = not core_b.broken;
    }
    if weapon == "shell" {
        live.table.rules = resolve_cores(live.table.rules, live.core_a_alive, live.core_b_alive);
    }
}

def _reveal_on(live: LiveMatch, outcome: SimOutcome, seat: str, now_ms: int, weapon: str) -> None {
    if _long(live) and live.world.impact_step < 0 {
        # A long shell that sails off the field still plays back for the shooter, with nothing revealed.
        trail = live.world.trace;
        flight_s = trail[len(trail) - 1] if len(trail) >= 3 else 0.0;
        live.reveal_seat = seat;
        live.reveal_x = trail[len(trail) - 3] if len(trail) >= 3 else 0.0;
        live.reveal_y = -50.0;
        live.reveal_radius = 0.0;
        live.reveal_until = server_now() + int(min(flight_s, 6.0) * 1000.0 / 1.6) + 1500;
        return;
    }
    if live.world.strike_step >= 0 {
        live.reveal_x = live.world.strike_x;
        live.reveal_y = live.world.strike_y;
    } elif live.world.impact_step >= 0 {
        live.reveal_x = live.world.impact_x;
        live.reveal_y = live.world.impact_y;
    } else {
        return;
    }
    live.reveal_seat = seat;
    live.reveal_until = server_now() + 3000;
    if _long(live) {
        # Long flights play back at 1.6x; keep the patch open through the flight and 3.5 s after.
        flight = live.world.blast_step if live.world.blast_step >= 0 else live.world.impact_step;
        flight_ms = int(float(max(0, flight)) * live.world.dt * 1000.0 / 1.6);
        live.reveal_until = server_now() + flight_ms + 3500;
        live.reveal_radius = 6.0 if weapon == "flare" else (4.5 if _powered(live, seat) else 3.5);
        return;
    }
    if weapon == "flare" {
        live.reveal_radius = 3.0;
    } elif _powered(live, seat) {
        live.reveal_radius = 2.6;
    } else {
        live.reveal_radius = 2.2;
    }
}

def _post_in_patch(live: LiveMatch) -> bool {
    limit = live.reveal_radius * live.reveal_radius + 0.0000001;
    for body in live.table.secrets {
        if body.id != "enemy-post" {
            continue;
        }
        dx = body.x - live.reveal_x;
        dy = body.y - live.reveal_y;
        return dx * dx + dy * dy <= limit;
    }
    return False;
}

def _bound(points: list[list[float]], limit: int) -> list[list[float]] {
    if len(points) <= limit {
        return points;
    }
    kept: list[list[float]] = [];
    # Ceiling step so the whole flight is covered, and the final sample (the landing) is kept.
    step = max(1, (len(points) + limit - 1) // limit);
    index = 0;
    while index < len(points) and len(kept) < limit {
        kept.append(points[index]);
        index = index + step;
    }
    last = points[len(points) - 1];
    if kept[len(kept) - 1] != last {
        if len(kept) >= limit {
            kept[len(kept) - 1] = last;
        } else {
            kept.append(last);
        }
    }
    return kept;
}

def _path_of(live: LiveMatch) -> list[list[float]] {
    points: list[list[float]] = [];
    index = 0;
    span = _field_width(live);
    while index + 2 < len(live.world.trace) {
        if _long(live) and (live.world.trace[index] < -2.0 or live.world.trace[index] > span + 2.0 or live.world.trace[index + 1] < -2.0) {
            break;
        }
        points.append([
            live.world.trace[index],
            live.world.trace[index + 1],
            live.world.trace[index + 2]
        ]);
        index = index + 3;
    }
    return _bound(points, 120 if _long(live) else 80);
}

def _series_for(live: LiveMatch, body_id: str) -> list[list[float]] {
    points: list[list[float]] = [];
    index = 0;
    name_at = 0;
    while index + 1 < len(live.world.collapse) {
        name = "";
        if name_at < len(live.world.collapse_names) {
            name = live.world.collapse_names[name_at];
        }
        if name == body_id {
            points.append([live.world.collapse[index], live.world.collapse[index + 1]]);
        }
        index = index + 2;
        name_at = name_at + 1;
    }
    return _bound(points, 80);
}

def _travel(points: list[list[float]]) -> float {
    if len(points) < 2 {
        return 0.0;
    }
    last = len(points) - 1;
    return abs(points[last][0] - points[0][0]);
}

def _choose_collapse(live: LiveMatch) -> None {
    enemy = _series_for(live, "enemy-post");
    home = _series_for(live, "post-a");
    if _travel(home) > _travel(enemy) {
        live.shot_collapse = home;
        live.shot_collapse_id = "post-a";
    } else {
        live.shot_collapse = enemy;
        live.shot_collapse_id = "enemy-post";
    }
}

def _body_in_patch(live: LiveMatch, body_id: str) -> bool {
    limit = live.reveal_radius * live.reveal_radius + 0.0000001;
    for body in live.table.secrets {
        if body.id != body_id {
            continue;
        }
        dx = body.x - live.reveal_x;
        dy = body.y - live.reveal_y;
        return dx * dx + dy * dy <= limit;
    }
    return False;
}

def _window_open(live: LiveMatch) -> bool {
    return live.reveal_until > 0 and server_now() < live.reveal_until;
}

def _in_reveal(live: LiveMatch, x: float, y: float) -> bool {
    dx = x - live.reveal_x;
    dy = y - live.reveal_y;
    limit = live.reveal_radius * live.reveal_radius + 0.0000001;
    return dx * dx + dy * dy <= limit;
}

def _filtered_path(live: LiveMatch, seat: str) -> list[list[float]] {
    points: list[list[float]] = [];
    if seat == "" or not _window_open(live) {
        return points;
    }
    mid = _field_width(live) / 2.0;
    # Long range: a shell bursts on first contact, so its free flight is public aim plus the
    # revealed burst point; the shooter follows the whole arc. The defender still sees only home.
    shooter = _long(live) and seat == live.reveal_seat;
    for point in live.shot_path {
        x = point[0];
        y = point[1];
        home = shooter;
        if seat == "A" and x <= mid {
            home = True;
        }
        if seat == "B" and x >= mid {
            home = True;
        }
        if home or (seat == live.reveal_seat and _in_reveal(live, x, y)) {
            points.append(point);
        }
    }
    return points;
}

def _filtered_collapse(live: LiveMatch, seat: str) -> list[list[float]] {
    empty: list[list[float]] = [];
    if seat == "" or not _window_open(live) {
        return empty;
    }
    body_id = live.shot_collapse_id;
    if body_id == "" {
        return empty;
    }
    owned = (seat == "B" and body_id == "enemy-post") or (seat == "A" and body_id == "post-a");
    if owned or _body_in_patch(live, body_id) {
        return live.shot_collapse;
    }
    return empty;
}

def _encode(
    live: LiveMatch,
    player_id: str,
    now_ms: int,
    ok: bool,
    code: str,
    weapon: str,
    broken: bool,
    angle: float
) -> str {
    seat = _seat(live, player_id);
    now = server_now();
    opened = seat != "" and seat == live.reveal_seat and now < live.reveal_until;
    expiry = live.reveal_until if opened else 0;
    view = project_view(
        seat,
        live.table.secrets,
        live.reveal_x,
        live.reveal_y,
        live.reveal_radius,
        opened,
        now,
        expiry
    );
    # Seat B owns the post. Seat A sees its pose only inside this reveal patch.
    visible = seat == "B" or (opened and _post_in_patch(live));
    shown_broken = broken if visible else False;
    shown_angle = angle if visible else 0.0;
    payload = {
        "ok": ok,
        "code": code,
        "seat": seat,
        "phase": live.table.rules.phase,
        "weapon": weapon,
        "broken": shown_broken,
        "angle": shown_angle,
        "path": _filtered_path(live, seat),
        "collapse": _filtered_collapse(live, seat),
        "collapse_id": live.shot_collapse_id if len(_filtered_collapse(live, seat)) > 0 else "",
        "your_turn": seat != "" and live.table.rules.active == seat and live.table.rules.phase != "finished" and live.table.rules.result == "",
        "reveal_until": expiry,
        "reveal_x": live.reveal_x if opened else 0.0,
        "reveal_y": live.reveal_y if opened else 0.0,
        "reveal_radius": live.reveal_radius if opened else 0.0,
        "result": live.table.rules.result,
        "perk": "scout" if _powered(live, seat) else "",
        "own_powered": _powered(live, seat),
        "shot_ready": _ready(live),
        "enemy_cores": _enemy_cores(live, seat),
        "own_core": _own_core(live, seat),
        "epoch": live.table.epoch,
        "turn": live.table.turn,
        "revision": live.table.revision,
        "room": live.table.invite,
        "view": json.loads(json.dumps(view.__dict__)),
        "ridge": _ridge(live),
        "layout_name": ridge_name(_ridge(live)),
        "terrain": _public_terrain(live),
        "field": _field(live)
    };
    if live.practice is not None {
        payload["mode"] = "practice";
        payload["bot_level"] = 1 + int(live.practice.get("streak", 0));
        payload["bot_thinking"] = live.table.rules.active == "B" and live.table.rules.phase != "finished";
        payload["bot_due_at"] = int(live.practice["due"]);
    }
    return json.dumps(payload);
}

def watch(live: LiveMatch, player_id: str, now_ms: int, weapon_override: str = "") -> str {
    broken = False;
    angle = 0.0;
    track = live.world.find("enemy-post");
    if track is not None {
        state = live.world.read_state(track);
        broken = state.broken;
        angle = state.angle;
    }
    weapon = weapon_override;
    if weapon == "" {
        weapon = "flare" if live.table.rules.phase == "recon" else "shell";
    }
    return _encode(live, player_id, now_ms, True, "", weapon, broken, angle);
}

def _launch(
    live: LiveMatch,
    seat: str,
    weapon: str,
    angle: float,
    power: float,
    now_ms: int,
    reveal: bool
) -> None {
    live.world.drop_projectiles();
    live.world.deal_damage = weapon == "shell";
    origin = _launcher(live, seat);
    long = _long(live);
    live.world.add_projectile(
        "shot",
        origin[0],
        origin[1],
        power * math.cos(angle),
        power * math.sin(angle),
        LONG_SHELL_R if long else 0.16
    );
    outcome = live.world.simulate(max_steps=LONG_STEPS if long else 1400);
    _apply_hit(live, outcome, weapon);
    if reveal {
        _reveal_on(live, outcome, seat, now_ms, weapon);
    }
}

def _replay(live: LiveMatch) -> None {
    for payload in live.table.payloads {
        parsed = _shot_parts(payload) as tuple[str, str, float, float, bool];
        if not parsed[4] {
            continue;
        }
        _launch(live, parsed[0], parsed[1], parsed[2], parsed[3], 0, False);
    }
}

def _stored(live: LiveMatch, command_id: str) -> int {
    index = 0;
    for item in live.table.commits {
        if item == command_id {
            return index;
        }
        index = index + 1;
    }
    return -1;
}

def take_shot(
    live: LiveMatch,
    player_id: str,
    command_id: str,
    pointer_x: float,
    pointer_y: float,
    canvas_w: float,
    canvas_h: float,
    dpr: float,
    epoch: int,
    expected_turn: int,
    expected_revision: int,
    weapon: str
) -> str {
    if live.refused {
        return _encode(live, player_id, server_now(), False, "snapshot", "", False, 0.0);
    }
    if live.table.in_flight {
        return _encode(live, player_id, server_now(), False, "busy", "", False, 0.0);
    }
    seat = _seat(live, player_id);
    if seat == "" {
        return _encode(live, player_id, server_now(), False, "unauthenticated", "", False, 0.0);
    }
    spot = _launcher(live, seat);
    aim = release_pull(seat, pointer_x, pointer_y, canvas_w, canvas_h, dpr, True, False, False, spot[0], spot[1]);
    if _long(live) {
        aim = release_long(seat, pointer_x, pointer_y, canvas_w, canvas_h, dpr, True, False, False);
    }
    if not aim.fired {
        return _encode(live, player_id, server_now(), False, aim.reason, "", False, 0.0);
    }
    stored = _stored(live, command_id);
    if stored >= 0 {
        same = _same_shot(live.table.payloads[stored], seat, weapon, aim.angle, aim.power, epoch) as bool;
        if same {
            return watch(live, player_id, server_now(), weapon);
        }
        if epoch != live.table.epoch {
            return _encode(live, player_id, server_now(), False, "epoch", weapon, False, 0.0);
        }
        return _encode(live, player_id, server_now(), False, "conflict", weapon, False, 0.0);
    }
    if epoch != live.table.epoch {
        return _encode(live, player_id, server_now(), False, "epoch", weapon, False, 0.0);
    }
    checked = accept_shot(
        live.table.rules, seat, expected_revision, expected_turn, weapon, aim.angle, aim.power,
        LONG_V_MAX if _long(live) else 22.0
    );
    if not checked.ok {
        return _encode(live, player_id, server_now(), False, checked.code, weapon, False, 0.0);
    }
    previous_practice = json.loads(json.dumps(live.practice));
    previous = copy_rules(live.table.rules);
    saved = live.world.capture();
    reveal_seat = live.reveal_seat;
    reveal_until = live.reveal_until;
    reveal_x = live.reveal_x;
    reveal_y = live.reveal_y;
    reveal_radius = live.reveal_radius;
    previous_path = live.shot_path;
    previous_collapse = live.shot_collapse;
    previous_collapse_id = live.shot_collapse_id;
    intact_a = True;
    intact_b = True;
    if live.mast_a is not None {
        intact_a = (live.mast_a as Site).intact;
    }
    if live.mast_b is not None {
        intact_b = (live.mast_b as Site).intact;
    }
    live.table.in_flight = True;
    shots_before = live.table.shots;
    added = False;
    committed = False;
    payload = "";
    try {
        _raise_if(live.table.fail_simulate);
        live.table.fail_simulate = False;
        live.table.rules = checked.state;
        _launch(live, seat, weapon, aim.angle, aim.power, server_now(), True);
        live.shot_path = _path_of(live);
        _choose_collapse(live);
        live.table.shots = shots_before + 1;
        live.table.turn = live.table.rules.turn;
        live.table.revision = live.table.rules.revision;
        payload = seat + "|" + str(live.table.revision) + "|" + str(live.table.turn) + "|" + weapon + "|" + str(aim.angle) + "|" + str(aim.power) + "|" + str(live.table.epoch);
        live.table.commits.append(command_id);
        live.table.payloads.append(payload);
        added = True;
        _practice_after_shot(live, seat);
        _save_canonical(live, live.table.fail_storage);
        live.table.fail_storage = False;
        committed = True;
    } except Exception {
        committed = False;
    }
    if not committed {
        live.practice = previous_practice;
        live.world.restore(saved);
        live.table.rules = previous;
        live.table.shots = shots_before;
        if added {
            _pop_last(live.table.commits);
            _pop_last(live.table.payloads);
        }
        live.table.turn = previous.turn;
        live.table.revision = previous.revision;
        live.reveal_seat = reveal_seat;
        live.reveal_until = reveal_until;
        live.reveal_x = reveal_x;
        live.reveal_y = reveal_y;
        live.reveal_radius = reveal_radius;
        live.shot_path = previous_path;
        live.shot_collapse = previous_collapse;
        live.shot_collapse_id = previous_collapse_id;
        if live.mast_a is not None {
            mast = live.mast_a as Site;
            mast.intact = intact_a;
        }
        if live.mast_b is not None {
            mast_b = live.mast_b as Site;
            mast_b.intact = intact_b;
        }
        _sync_post(live);
        _refresh_cores(live);
        live.table.in_flight = False;
        live.table.fail_storage = False;
        live.table.fail_simulate = False;
        return _encode(live, player_id, server_now(), False, "interrupted", weapon, False, 0.0);
    }
    try {
        write_commit_line(live.table, command_id, payload);
    } except Exception {
        payload = payload;
    }
    live.table.in_flight = False;
    broken = False;
    angle = 0.0;
    post = live.world.find("enemy-post");
    if post is not None {
        state = live.world.read_state(post);
        broken = state.broken;
        angle = state.angle;
    }
    return _encode(live, player_id, server_now(), True, "", weapon, broken, angle);
}

def _clear_journal(directory: str, preserve_snapshot: bool = False) -> None {
    Path(directory + "/journal.jsonl").write_text("");
    pending = Path(directory + "/pending.json");
    if pending.exists() {
        pending.unlink();
    }
    canonical = Path(directory + "/canonical.json");
    if canonical.exists() and not preserve_snapshot {
        canonical.unlink();
    }
}

def rematch_room(live: LiveMatch, player_id: str, ridge: int = -1) -> str {
    seat = _seat(live, player_id);
    if seat == "" {
        return _encode(live, player_id, 0, False, "unauthenticated", "", False, 0.0);
    }
    # A shared ridge may replace a duel nobody has fired in yet; otherwise only a finished duel restarts.
    untouched = ridge >= 0 and live.table.turn == 0 and live.table.rules.phase == "recon" and ridge != _ridge(live);
    if live.table.rules.phase != "finished" and not untouched {
        return _encode(live, player_id, 0, False, "active", "", False, 0.0);
    }
    return _restart(live, player_id, ridge);
}

# A new duel on a new layout. ridge -1 always draws a fresh random ridge.
def _restart(live: LiveMatch, player_id: str, ridge: int) -> str {
    previous_layout = live.layout;
    live.layout = make_layout(ridge);
    live.table.rules = MatchRules();
    live.table.shots = 0;
    live.table.turn = 0;
    live.table.revision = 0;
    live.table.epoch = live.table.epoch + 1;
    live.table.commits = [];
    live.table.payloads = [];
    live.table.in_flight = False;
    live.reveal_seat = "";
    live.reveal_until = 0;
    live.reveal_x = 0.0;
    live.reveal_y = 0.0;
    live.shot_path = [];
    live.shot_collapse = [];
    live.shot_collapse_id = "";
    if live.mast_a is not None {
        mast = live.mast_a as Site;
        mast.intact = True;
    }
    if live.mast_b is not None {
        mast_b = live.mast_b as Site;
        mast_b.intact = True;
    }
    _arm(live);
    if live.practice is not None {
        live.practice["memory"] = new_memory(live.table.epoch);
        live.practice["due"] = 0;
        live.practice["plan"] = None;
        try {
            _save_canonical(live, live.table.fail_storage);
            live.table.fail_storage = False;
        } except Exception {
            live.layout = previous_layout;
            _arm(live);
            _load_canonical(live);
            live.table.fail_storage = False;
            return _encode(live, player_id, 0, False, "interrupted", "", False, 0.0);
        }
        _write_layout(live.table.directory, live.layout);
        _clear_journal(live.table.directory, True);
    } else {
        _write_layout(live.table.directory, live.layout);
        _clear_journal(live.table.directory);
    }
    save_seats(live.table);
    return watch(live, player_id, 0);
}


def boot_practice(directory: str, owner: str, invite: str = "aabbcc", ridge: int = 0) -> LiveMatch {
    live = boot_match(directory, invite, ridge);
    if live.practice is None {
        live.table.seat_a = owner;
        live.table.seat_b = "practice-bot-" + str(_fresh_code() as str);
        live.practice = {"owner": owner, "bot": live.table.seat_b,
            "memory": new_memory(live.table.epoch), "due": 0, "plan": None,
            "streak": 0, "scored": 0, "bot_seed": int(str(_fresh_code() as str), 16)};
        _save_canonical(live, False);
        save_seats(live.table);
    }
    return live;
}

def open_practice(owner: str, ridge: int = -1) -> str {
    with _room_lock("__create__") {
        for attempt in range(8) {
            code = str(_practice_code(owner, attempt) as str);
            with _room_lock(code) {
                found = room_match(code);
                if found is not None {
                    existing = found as LiveMatch;
                    if existing.practice is not None and str(existing.practice["owner"]) == owner {
                        # An explicit shared ridge replaces an untouched or finished duel only.
                        quiet = existing.table.rules.phase == "finished" or existing.table.turn == 0;
                        if ridge >= 0 and ridge != _ridge(existing) and quiet {
                            with _room_lock(existing.table.directory) {
                                _restart(existing, owner, ridge);
                            }
                        }
                        return code;
                    }
                    continue;
                }
                live = _publish_practice(ROOM_ROOT + "/" + code, owner, code, boot_practice, ridge) as LiveMatch;
                _remember_room(code, live);
                return code;
            }
        }
    }
    return "";
}

def _visit(live: LiveMatch, player: str) -> bool {
    if live.practice is not None {
        if player != str(live.practice["owner"]) {
            return False;
        }
        live.table.seat_a = player;
        live.table.seat_b = str(live.practice["bot"]);
        live.table.seen_a = server_now();
        live.table.seen_b = server_now();
        save_seats(live.table);
    } else {
        release_stale(live.table, server_now());
        note_seen(live.table, player, server_now());
    }
    return True;
}

def _practice_after_shot(live: LiveMatch, seat: str) -> None {
    if live.practice is None {
        return;
    }
    if seat == "B" {
        # This is the identical redacted observation available to a human B seat.
        observation = watch(live, str(live.practice["bot"]), server_now());
        live.practice["memory"] = learn(observation, str(live.practice["memory"]), server_now());
    }
    live.practice["plan"] = None;
    live.practice["due"] = 0;
    if live.table.rules.result != "" and int(live.practice.get("scored", 0)) != live.table.epoch {
        # The bot sharpens while the human keeps winning and relaxes after a loss.
        live.practice["scored"] = live.table.epoch;
        live.practice["streak"] = int(live.practice.get("streak", 0)) + 1 if live.table.rules.result == "A" else 0;
    }
    if live.table.rules.active == "B" and live.table.rules.phase != "finished" {
        live.practice["due"] = max(server_now() + 1200, live.reveal_until + 400);
    }
}

def practice_watch(live: LiveMatch, player: str) -> str {
    with _room_lock(live.table.directory) {
        if live.practice is None or player != str(live.practice["owner"]) {
            return _closed();
        }
        if live.table.rules.phase == "finished" or live.table.rules.active != "B" or server_now() < int(live.practice["due"]) {
            return watch(live, player, server_now());
        }
        if live.practice["plan"] is None {
            observation = watch(live, str(live.practice["bot"]), server_now());
            skill = json.dumps({"seed": int(live.practice.get("bot_seed", 0)), "streak": int(live.practice.get("streak", 0))});
            plan = json.loads(choose(observation, str(live.practice["memory"]), skill));
            if not bool(plan.get("ready", False)) {
                return watch(live, player, server_now());
            }
            plan["epoch"] = live.table.epoch;
            plan["turn"] = live.table.turn;
            plan["revision"] = live.table.revision;
            plan["command"] = "practice:B:" + str(live.table.epoch) + ":" + str(live.table.turn) + ":" + str(live.table.revision);
            live.practice["plan"] = plan;
            try {
                _save_canonical(live, False);
            } except Exception {
                live.practice["plan"] = None;
                return _encode(live, player, 0, False, "interrupted", "", False, 0.0);
            }
        }
        plan = live.practice["plan"];
        take_shot(live, str(live.practice["bot"]), str(plan["command"]),
            float(plan["x"]), float(plan["y"]), 800.0, 400.0, 1.0,
            int(plan["epoch"]), int(plan["turn"]), int(plan["revision"]), str(plan["weapon"]));
        return watch(live, player, server_now());
    }
}

def _wanted_ridge(ridge: any) -> int {
    # Shared links name a ridge; anything else (missing, malformed, out of range) draws a fresh one.
    text = str(ridge if ridge is not None else "").strip();
    if text == "" or len(text) > 5 or not text.isdigit() {
        return -1;
    }
    return int(text);
}

def:protect create_practice(ridge: str = "") -> str {
    code = open_practice(str(jid(root)), _wanted_ridge(ridge));
    if code == "" {
        return "{\"ok\": false, \"code\": \"full\", \"room\": \"\"}";
    }
    return json.dumps({"ok": True, "code": "", "room": code});
}

def _closed() -> str {
    return "{\"ok\": false, \"code\": \"unauthenticated\", \"seat\": \"\"}";
}

def:protect create_room(ridge: str = "") -> str {
    code = open_room(_wanted_ridge(ridge));
    if code == "" {
        return "{\"ok\": false, \"code\": \"full\", \"room\": \"\"}";
    }
    return "{\"ok\": true, \"code\": \"\", \"room\": \"" + code + "\"}";
}

def:protect release_seat(invite: str) -> str {
    found = _match_for(invite);
    if found is None {
        return _closed();
    }
    live = found as LiveMatch;
    with _room_lock(live.table.directory) {
        player = str(jid(root));
        if not _visit(live, player) { return _closed(); }
        if live.practice is None {
            release_player(live.table, player);
        }
        return "{\"ok\": true, \"code\": \"released\", \"seat\": \"\"}";
    }
}

# The Rematch button sends no ridge and always rolls a fresh one. An explicit
# ridge replays that shared ridge (finished or untouched duels only).
def:protect play_again(invite: str, ridge: str = "") -> str {
    found = _match_for(invite);
    if found is None {
        return _closed();
    }
    live = found as LiveMatch;
    with _room_lock(live.table.directory) {
        player = str(jid(root));
        if not _visit(live, player) {
            return _closed();
        }
        return rematch_room(live, player, _wanted_ridge(ridge));
    }
}

def:protect join_seat(invite: str) -> str {
    found = _match_for(invite);
    if found is None {
        return _closed();
    }
    live = found as LiveMatch;
    with _room_lock(live.table.directory) {
        player = str(jid(root));
        if not _visit(live, player) {
            return _closed();
        }
        claimed = claim(live.table, player, invite);
        if not claimed.ok {
            return _encode(live, player, 0, False, claimed.code, "", False, 0.0);
        }
        note_seen(live.table, player, server_now());
        return watch(live, player, 0);
    }
}

def:protect watch_match(invite: str, now_ms: int) -> str {
    found = _match_for(invite);
    if found is None {
        return _closed();
    }
    live = found as LiveMatch;
    with _room_lock(live.table.directory) {
        player = str(jid(root));
        if not _visit(live, player) {
            return _closed();
        }
        if live.practice is not None {
            return practice_watch(live, player);
        }
        return watch(live, player, server_now());
    }
}

def:protect loose_shot(
    invite: str,
    command_id: str,
    epoch: int,
    expected_turn: int,
    expected_revision: int,
    weapon: str,
    pointer_x: float,
    pointer_y: float,
    canvas_w: float,
    canvas_h: float,
    dpr: float
) -> str {
    found = _match_for(invite);
    if found is None {
        return _closed();
    }
    live = found as LiveMatch;
    with _room_lock(live.table.directory) {
        player = str(jid(root));
        if not _visit(live, player) {
            return _closed();
        }
        return take_shot(
            live,
            player,
            command_id,
            pointer_x,
            pointer_y,
            canvas_w,
            canvas_h,
            dpr,
            epoch,
            expected_turn,
            expected_revision,
            weapon
        );
    }
}
