"""One shared match. A canvas pull becomes the Pymunk shot, and the wire is an allowlist."""

import json;
import math;
import from pathlib { Path }
import from game.aim { launcher_for, release_pull }
import from game.rules { MatchRules, accept_shot, copy_rules, resolve_cores }
import from graph.supply { Cable, Site, assess }
import from physics.pymunk_driver { BodyState, PhysicsWorld, SimOutcome }
import from server.authority { ClaimResult, Table, append_commit, claim, reload_table, save_seats, submit }
import from server.clock { server_now }
import from server.views { SecretBody, project_view }

::py::
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
}

glob _shared: LiveMatch | None = None;

def _chain(owner: str, source_name: str, mast_name: str, core_name: str) -> tuple[Site, Site, Site] {
    source = Site(name=source_name, owner=owner, kind="source", intact=True);
    mast = Site(name=mast_name, owner=owner, kind="link", intact=True);
    core = Site(name=core_name, owner=owner, kind="objective", intact=True);
    source +>:Cable():+> mast;
    mast +>:Cable():+> core;
    return (source, mast, core);
}

def _arm(live: LiveMatch) -> None {
    world = PhysicsWorld();
    world.add_ground("ground", -2.0, 0.0, 42.0, 0.0);
    # Pointer (20, 300) on an 800 by 400 canvas is angle 0 at power 5.
    # That shell breaks the braced mast. The static core at (11.2, 2.6)
    # sits above that roll and stays alive until the higher shell.
    # The siege fixture (x=20, health 4, angle 0.15, power 14) is unchanged.
    # Clearance 0.22 keeps a flat shell on the post. The 0.35 siege pivot
    # lets a fraction of a degree slip underneath that thin brace.
    world.add_braced_post("enemy-post", 21.0, 0.0, 0.14, 3.2, 0.22, 0.5, 0.22);
    world.add_static_box("core-b", 11.2, 2.6, 0.8, 0.8, 0.4);
    world.add_static_box("core-a", 4.25, 3.25, 0.8, 0.8, 0.4);
    live.world = world;
    live.core_a_alive = True;
    live.core_b_alive = True;
    live.table.secrets = [
        SecretBody(
            id="launcher-a", owner="A", x=6.0, y=4.0, w=0.4, h=0.4,
            angle=0.0, role="launcher", alive=True, health=1.0
        ),
        SecretBody(
            id="core-a", owner="A", x=4.25, y=3.25, w=0.8, h=0.8,
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

def boot_match(directory: str) -> LiveMatch {
    Path(directory).mkdir(parents=True, exist_ok=True);
    table = reload_table("fogshot", directory);
    live = LiveMatch(table=table, world=PhysicsWorld());
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
        "bodies": bodies
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
    return True;
}

def shared_match() -> LiveMatch {
    if _shared is None {
        _shared = boot_match("runtime-data/browser-match");
    }
    return _shared as LiveMatch;
}

def claim_player(live: LiveMatch, player_id: str) -> ClaimResult {
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
    for body_id in ["enemy-post", "core-a", "core-b"] {
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

def _reveal_on(live: LiveMatch, outcome: SimOutcome, seat: str, now_ms: int) -> None {
    target = "";
    if seat == "A" and outcome.contacted("shot", "core-b") {
        target = "core-b";
    } elif seat == "B" and outcome.contacted("shot", "core-a") {
        target = "core-a";
    } elif outcome.contacted("shot", "enemy-post") {
        target = "enemy-post";
    }
    if target == "" {
        return;
    }
    hit = outcome.body(target);
    live.reveal_seat = seat;
    live.reveal_until = server_now() + 3000;
    live.reveal_x = hit.x;
    live.reveal_y = hit.y;
    live.reveal_radius = 4.0;
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

def _path_of(live: LiveMatch) -> list[list[float]] {
    points: list[list[float]] = [];
    index = 0;
    while index + 1 < len(live.world.trace) {
        points.append([live.world.trace[index], live.world.trace[index + 1]]);
        index = index + 2;
    }
    return points;
}

def _encode(
    live: LiveMatch,
    player_id: str,
    now_ms: int,
    ok: bool,
    code: str,
    weapon: str,
    path: list[list[float]],
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
        "path": path,
        "reveal_until": expiry,
        "result": live.table.rules.result,
        "own_powered": _powered(live, seat),
        "shot_ready": _ready(live),
        "enemy_cores": _enemy_cores(live, seat),
        "own_core": _own_core(live, seat),
        "epoch": live.table.epoch,
        "turn": live.table.turn,
        "revision": live.table.revision,
        "view": json.loads(json.dumps(view.__dict__))
    };
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
    return _encode(live, player_id, now_ms, True, "", weapon, [], broken, angle);
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
    origin = launcher_for(seat);
    live.world.add_projectile(
        "shot",
        origin[0],
        origin[1],
        power * math.cos(angle),
        power * math.sin(angle),
        0.16
    );
    outcome = live.world.simulate(max_steps=1400);
    _apply_hit(live, outcome, weapon);
    if reveal {
        _reveal_on(live, outcome, seat, now_ms);
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
        return _encode(live, player_id, server_now(), False, "snapshot", "", [], False, 0.0);
    }
    if live.table.in_flight {
        return _encode(live, player_id, server_now(), False, "busy", "", [], False, 0.0);
    }
    seat = _seat(live, player_id);
    if seat == "" {
        return _encode(live, player_id, server_now(), False, "unauthenticated", "", [], False, 0.0);
    }
    aim = release_pull(seat, pointer_x, pointer_y, canvas_w, canvas_h, dpr, True, False, False);
    if not aim.fired {
        return _encode(live, player_id, server_now(), False, aim.reason, "", [], False, 0.0);
    }
    stored = _stored(live, command_id);
    if stored >= 0 {
        same = _same_shot(live.table.payloads[stored], seat, weapon, aim.angle, aim.power, epoch) as bool;
        if same {
            return watch(live, player_id, server_now(), weapon);
        }
        if epoch != live.table.epoch {
            return _encode(live, player_id, server_now(), False, "epoch", weapon, [], False, 0.0);
        }
        return _encode(live, player_id, server_now(), False, "conflict", weapon, [], False, 0.0);
    }
    if epoch != live.table.epoch {
        return _encode(live, player_id, server_now(), False, "epoch", weapon, [], False, 0.0);
    }
    checked = accept_shot(
        live.table.rules, seat, expected_revision, expected_turn, weapon, aim.angle, aim.power
    );
    if not checked.ok {
        return _encode(live, player_id, server_now(), False, checked.code, weapon, [], False, 0.0);
    }
    previous = copy_rules(live.table.rules);
    saved = live.world.capture();
    reveal_seat = live.reveal_seat;
    reveal_until = live.reveal_until;
    reveal_x = live.reveal_x;
    reveal_y = live.reveal_y;
    reveal_radius = live.reveal_radius;
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
        live.table.shots = shots_before + 1;
        live.table.turn = live.table.rules.turn;
        live.table.revision = live.table.rules.revision;
        payload = seat + "|" + str(live.table.revision) + "|" + str(live.table.turn) + "|" + weapon + "|" + str(aim.angle) + "|" + str(aim.power) + "|" + str(live.table.epoch);
        live.table.commits.append(command_id);
        live.table.payloads.append(payload);
        added = True;
        _save_canonical(live, live.table.fail_storage);
        live.table.fail_storage = False;
        committed = True;
    } except Exception {
        committed = False;
    }
    if not committed {
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
        return _encode(live, player_id, server_now(), False, "interrupted", weapon, [], False, 0.0);
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
    return _encode(live, player_id, server_now(), True, "", weapon, _path_of(live), broken, angle);
}

def _clear_journal(directory: str) -> None {
    Path(directory + "/journal.jsonl").write_text("");
    pending = Path(directory + "/pending.json");
    if pending.exists() {
        pending.unlink();
    }
    canonical = Path(directory + "/canonical.json");
    if canonical.exists() {
        canonical.unlink();
    }
}

def rematch_room(live: LiveMatch, player_id: str) -> str {
    seat = _seat(live, player_id);
    if seat == "" {
        return _encode(live, player_id, 0, False, "unauthenticated", "", [], False, 0.0);
    }
    if live.table.rules.phase != "finished" {
        return _encode(live, player_id, 0, False, "active", "", [], False, 0.0);
    }
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
    if live.mast_a is not None {
        mast = live.mast_a as Site;
        mast.intact = True;
    }
    if live.mast_b is not None {
        mast_b = live.mast_b as Site;
        mast_b.intact = True;
    }
    _arm(live);
    _clear_journal(live.table.directory);
    save_seats(live.table);
    return watch(live, player_id, 0);
}

def:protect play_again(invite: str) -> str {
    if invite != "fogshot" {
        return "{\"ok\": false, \"code\": \"unauthenticated\", \"seat\": \"\"}";
    }
    return rematch_room(shared_match(), str(jid(root)));
}

def:protect join_seat(invite: str) -> str {
    if invite != "fogshot" {
        return "{\"ok\": false, \"code\": \"unauthenticated\", \"seat\": \"\"}";
    }
    player = str(jid(root));
    live = shared_match();
    claimed = claim(live.table, player, invite);
    if not claimed.ok {
        return _encode(live, player, 0, False, claimed.code, "", [], False, 0.0);
    }
    return watch(live, player, 0);
}

def:protect watch_match(invite: str, now_ms: int) -> str {
    if invite != "fogshot" {
        return "{\"ok\": false, \"code\": \"unauthenticated\", \"seat\": \"\"}";
    }
    return watch(shared_match(), str(jid(root)), server_now());
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
    if invite != "fogshot" {
        return "{\"ok\": false, \"code\": \"unauthenticated\", \"seat\": \"\"}";
    }
    return take_shot(
        shared_match(),
        str(jid(root)),
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
