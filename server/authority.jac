"""One in-process match journal. Seats are player ids. The invite only opens a chair.

The pending file is the pre-shot checkpoint. A commit line is the outcome and the
next turn together. Reload keeps commit lines and deletes a pending file, so a
crash before the commit does not leave a second shot.
"""

import json;
import from pathlib { Path }
import from game.rules { MatchRules, accept_shot }
import from server.views { SecretBody, project_view }

obj Table {
    has invite: str;
    has directory: str;
    has seat_a: str = "";
    has seat_b: str = "";
    has rules: MatchRules = MatchRules();
    has shots: int = 0;
    has turn: int = 0;
    has revision: int = 0;
    has in_flight: bool = False;
    has fail_before_commit: bool = False;
    has force_finished: bool = False;
    has commits: list[str] = [];
    has payloads: list[str] = [];
    has secrets: list[SecretBody] = [];
}

obj ClaimResult {
    has ok: bool;
    has code: str = "";
    has seat: str = "";
}

obj SubmitResult {
    has ok: bool;
    has code: str = "";
    has turn: int = 0;
    has revision: int = 0;
    has shots: int = 0;
}

def _blank(invite: str, directory: str) -> Table {
    return Table(
        invite=invite,
        directory=directory,
        rules=MatchRules(),
        commits=[],
        payloads=[],
        secrets=[]
    );
}

def _seats_path(directory: str) -> str {
    return directory + "/seats.json";
}

def _journal_path(directory: str) -> str {
    return directory + "/journal.jsonl";
}

def _pending_path(directory: str) -> str {
    return directory + "/pending.json";
}

def _write_text(path: str, text: str) -> None {
    Path(path).write_text(text);
}

def _read_text(path: str) -> str {
    file = Path(path);
    if not file.exists() {
        return "";
    }
    return file.read_text();
}

def _write_seats(table: Table) -> None {
    _write_text(_seats_path(table.directory), json.dumps({
        "A": table.seat_a,
        "B": table.seat_b
    }));
}

def _payload(actor: str, revision: int, turn: int, weapon: str, angle: float, power: float) -> str {
    return actor + "|" + str(revision) + "|" + str(turn) + "|" + weapon + "|" + str(angle) + "|" + str(power);
}

def _result(ok: bool, code: str, table: Table) -> SubmitResult {
    return SubmitResult(
        ok=ok,
        code=code,
        turn=table.turn,
        revision=table.revision,
        shots=table.shots
    );
}

def _seat_of(table: Table, player_id: str) -> str {
    if player_id != "" and player_id == table.seat_a {
        return "A";
    }
    if player_id != "" and player_id == table.seat_b {
        return "B";
    }
    return "";
}

def _commit_index(table: Table, command_id: str) -> int {
    index = 0;
    for item in table.commits {
        if item == command_id {
            return index;
        }
        index = index + 1;
    }
    return -1;
}

def open_table(invite: str, directory: str) -> Table {
    Path(directory).mkdir(parents=True, exist_ok=True);
    table = _blank(invite, directory);
    _write_seats(table);
    return table;
}

def claim(table: Table, player_id: str, invite: str) -> ClaimResult {
    if player_id == "" or invite != table.invite {
        return ClaimResult(ok=False, code="unauthenticated");
    }
    seated = _seat_of(table, player_id);
    if seated != "" {
        return ClaimResult(ok=True, seat=seated);
    }
    if table.seat_a == "" {
        table.seat_a = player_id;
        _write_seats(table);
        return ClaimResult(ok=True, seat="A");
    }
    if table.seat_b == "" {
        table.seat_b = player_id;
        _write_seats(table);
        return ClaimResult(ok=True, seat="B");
    }
    return ClaimResult(ok=False, code="full");
}

def look(table: Table, player_id: str) -> str {
    seat = _seat_of(table, player_id);
    if seat == "" {
        return "{}";
    }
    view = project_view(seat, table.secrets, 0.0, 0.0, 0.0, False, 0, 0);
    return json.dumps(view.__dict__);
}

def _append_commit(table: Table, command_id: str, payload: str) -> None {
    line = json.dumps({
        "id": command_id,
        "payload": payload,
        "shots": table.shots,
        "turn": table.turn,
        "revision": table.revision,
        "phase": table.rules.phase,
        "active": table.rules.active,
        "result": table.rules.result,
        "flare_a": table.rules.flare_a,
        "flare_b": table.rules.flare_b
    });
    current = _read_text(_journal_path(table.directory));
    _write_text(_journal_path(table.directory), current + line + "\n");
    table.commits.append(command_id);
    table.payloads.append(payload);
}

def _drop_pending(directory: str) -> None {
    file = Path(_pending_path(directory));
    if file.exists() {
        file.unlink();
    }
}

def submit(
    table: Table,
    player_id: str,
    invite: str,
    command_id: str,
    actor: str,
    revision: int,
    turn: int,
    weapon: str,
    angle: float,
    power: float
) -> SubmitResult {
    if player_id == "" or invite != table.invite {
        return _result(False, "unauthenticated", table);
    }
    if table.in_flight {
        return _result(False, "busy", table);
    }
    seat = _seat_of(table, player_id);
    if seat == "" {
        return _result(False, "unauthenticated", table);
    }
    if actor != seat {
        return _result(False, "actor", table);
    }
    payload = _payload(actor, revision, turn, weapon, angle, power);
    existing = _commit_index(table, command_id);
    if existing >= 0 {
        if table.payloads[existing] == payload {
            return _result(True, "", table);
        }
        return _result(False, "conflict", table);
    }
    if table.force_finished {
        table.rules.phase = "finished";
        table.rules.result = "draw";
    }
    decision = accept_shot(table.rules, actor, revision, turn, weapon, angle, power);
    if not decision.ok {
        return _result(False, decision.code, table);
    }
    table.in_flight = True;
    _write_text(_pending_path(table.directory), json.dumps({
        "id": command_id,
        "payload": payload,
        "checkpoint_shots": table.shots,
        "checkpoint_turn": table.turn,
        "checkpoint_revision": table.revision
    }));
    if table.fail_before_commit {
        table.in_flight = False;
        table.fail_before_commit = False;
        return _result(False, "interrupted", table);
    }
    table.rules = decision.state;
    table.shots = table.shots + 1;
    table.turn = table.rules.turn;
    table.revision = table.rules.revision;
    _append_commit(table, command_id, payload);
    _drop_pending(table.directory);
    table.in_flight = False;
    return _result(True, "", table);
}

def reload_table(invite: str, directory: str) -> Table {
    table = _blank(invite, directory);
    seats_raw = _read_text(_seats_path(directory));
    if seats_raw != "" {
        seats = json.loads(seats_raw);
        table.seat_a = str(seats["A"]);
        table.seat_b = str(seats["B"]);
    }
    raw = _read_text(_journal_path(directory));
    for line in raw.split("\n") {
        if line == "" {
            continue;
        }
        row = json.loads(line);
        table.commits.append(str(row["id"]));
        table.payloads.append(str(row["payload"]));
        table.shots = int(row["shots"]);
        table.turn = int(row["turn"]);
        table.revision = int(row["revision"]);
        table.rules = MatchRules(
            phase=str(row["phase"]),
            turn=int(row["turn"]),
            revision=int(row["revision"]),
            active=str(row["active"]),
            result=str(row["result"]),
            flare_a=bool(row["flare_a"]),
            flare_b=bool(row["flare_b"])
        );
    }
    _drop_pending(directory);
    return table;
}
