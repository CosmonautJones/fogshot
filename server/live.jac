"""One shared match. A canvas pull becomes the Pymunk shot, and the wire is an allowlist."""

import json;
import math;
import from pathlib { Path }
import from game.aim { launcher_for, release_pull }
import from game.rules { MatchRules, resolve_cores }
import from graph.supply { Cable, Site, assess }
import from physics.pymunk_driver { PhysicsWorld, SimOutcome }
import from server.authority { ClaimResult, Table, claim, open_table, submit }
import from server.views { SecretBody, project_view }

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
    world.add_braced_post("enemy-post", 21.0, 0.0, 0.14, 3.2, 0.22, 0.5);
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
    table = open_table("fogshot", directory);
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
    return live;
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
    live.reveal_until = now_ms + 3000;
    live.reveal_x = hit.x;
    live.reveal_y = hit.y;
    live.reveal_radius = 4.0;
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
    opened = seat != "" and seat == live.reveal_seat and now_ms < live.reveal_until;
    expiry = live.reveal_until if opened else 0;
    view = project_view(
        seat,
        live.table.secrets,
        live.reveal_x,
        live.reveal_y,
        live.reveal_radius,
        opened,
        now_ms,
        expiry
    );
    visible = seat == "B" or opened;
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
        "view": json.loads(json.dumps(view.__dict__))
    };
    return json.dumps(payload);
}

def watch(live: LiveMatch, player_id: str, now_ms: int) -> str {
    broken = False;
    angle = 0.0;
    track = live.world.find("enemy-post");
    if track is not None {
        state = live.world.read_state(track);
        broken = state.broken;
        angle = state.angle;
    }
    weapon = "flare" if live.table.rules.phase == "recon" else "shell";
    return _encode(live, player_id, now_ms, True, "", weapon, [], broken, angle);
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
    now_ms: int
) -> str {
    seat = _seat(live, player_id);
    if seat == "" {
        return _encode(live, player_id, now_ms, False, "unauthenticated", "", [], False, 0.0);
    }
    aim = release_pull(seat, pointer_x, pointer_y, canvas_w, canvas_h, dpr, True, False, False);
    if not aim.fired {
        return _encode(live, player_id, now_ms, False, aim.reason, "", [], False, 0.0);
    }
    weapon = "flare" if live.table.rules.phase == "recon" else "shell";
    before = live.table.shots;
    decision = submit(
        live.table,
        player_id,
        live.table.invite,
        command_id,
        seat,
        live.table.revision,
        live.table.turn,
        weapon,
        aim.angle,
        aim.power
    );
    if not decision.ok {
        return _encode(live, player_id, now_ms, False, decision.code, weapon, [], False, 0.0);
    }
    if decision.shots == before {
        return watch(live, player_id, now_ms);
    }
    live.world.drop_projectiles();
    live.world.deal_damage = weapon == "shell";
    origin = launcher_for(seat);
    live.world.add_projectile(
        "shot",
        origin[0],
        origin[1],
        aim.power * math.cos(aim.angle),
        aim.power * math.sin(aim.angle),
        0.16
    );
    outcome = live.world.simulate(max_steps=1400);
    _apply_hit(live, outcome, weapon);
    _reveal_on(live, outcome, seat, now_ms);
    broken = False;
    angle = 0.0;
    post = live.world.find("enemy-post");
    if post is not None {
        state = live.world.read_state(post);
        broken = state.broken;
        angle = state.angle;
    }
    return _encode(live, player_id, now_ms, True, "", weapon, _path_of(live), broken, angle);
}

def _clear_journal(directory: str) -> None {
    Path(directory + "/journal.jsonl").write_text("");
    pending = Path(directory + "/pending.json");
    if pending.exists() {
        pending.unlink();
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
    claim(live.table, player, invite);
    return watch(live, player, 0);
}

def:protect watch_match(invite: str, now_ms: int) -> str {
    if invite != "fogshot" {
        return "{\"ok\": false, \"code\": \"unauthenticated\", \"seat\": \"\"}";
    }
    return watch(shared_match(), str(jid(root)), now_ms);
}

def:protect loose_shot(
    invite: str,
    command_id: str,
    pointer_x: float,
    pointer_y: float,
    canvas_w: float,
    canvas_h: float,
    dpr: float,
    now_ms: int
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
        now_ms
    );
}
