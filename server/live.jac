"""One shared match. A canvas pull becomes the Pymunk shot, and the wire is an allowlist."""

import json;
import math;
import from game.aim { launcher_for, release_pull }
import from physics.pymunk_driver { PhysicsWorld }
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
}

glob _shared: LiveMatch | None = None;

def boot_match(directory: str) -> LiveMatch {
    table = open_table("fogshot", directory);
    world = PhysicsWorld();
    world.add_ground("ground", -2.0, 0.0, 42.0, 0.0);
    # Pointer (20, 300) on an 800 by 400 canvas is angle 0 at power 5.
    # That shell's first impulse is about 0.76, so health 0.5 breaks on it.
    # The siege fixture (x=20, health 4, angle 0.15, power 14) is a different shot.
    world.add_braced_post("enemy-post", 21.0, 0.0, 0.14, 3.2, 0.22, 0.5);
    live = LiveMatch(table=table, world=world);
    live.table.secrets = [
        SecretBody(
            id="launcher-a", owner="A", x=6.0, y=4.0, w=0.4, h=0.4,
            angle=0.0, role="launcher", alive=True, health=1.0
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
    track = live.world.find("enemy-post");
    if track is None {
        return;
    }
    state = live.world.read_state(track);
    for body in live.table.secrets {
        if body.id == "enemy-post" {
            body.x = state.x;
            body.y = state.y;
            body.angle = state.angle;
            body.health = state.health;
            body.alive = not state.broken;
        }
    }
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
    _sync_post(live);
    broken = False;
    angle = 0.0;
    post = live.world.find("enemy-post");
    if post is not None {
        state = live.world.read_state(post);
        broken = state.broken;
        angle = state.angle;
    }
    if outcome.contacted("shot", "enemy-post") {
        hit = outcome.body("enemy-post");
        live.reveal_seat = seat;
        live.reveal_until = now_ms + 3000;
        live.reveal_x = hit.x;
        live.reveal_y = hit.y;
        live.reveal_radius = 4.0;
        broken = hit.broken;
        angle = hit.angle;
    }
    return _encode(live, player_id, now_ms, True, "", weapon, _path_of(live), broken, angle);
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
