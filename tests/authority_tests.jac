"""Two seats, one journal. An invite code is not permission to shoot."""

import json;
import tempfile;
import from pathlib { Path }
import from server.authority { claim, look, open_table, reload_table, submit }
import from server.views { SecretBody }

def _dir() -> str {
    return tempfile.mkdtemp(prefix="fogshot-");
}

def _seat(table: any, player_id: str, invite: str) -> any {
    return claim(table, player_id, invite);
}

test "a third player cannot replace a seat" {
    invite = "room-seats";
    directory = _dir();
    table = open_table(invite, directory);
    first = _seat(table, "player-a", invite);
    second = _seat(table, "player-b", invite);
    third = _seat(table, "player-c", invite);
    assert first.ok and first.seat == "A";
    assert second.ok and second.seat == "B";
    assert not third.ok;
    assert third.code == "full";
    again = _seat(table, "player-a", invite);
    assert again.ok and again.seat == "A";
}

test "an invite code is not shot authority" {
    invite = "room-invite";
    directory = _dir();
    table = open_table(invite, directory);
    _seat(table, "player-a", invite);
    _seat(table, "player-b", invite);
    refused = submit(table, "", invite, "cmd-guest", "A", 0, 0, "flare", 0.4, 5.0);
    assert not refused.ok;
    assert refused.code == "unauthenticated";
    assert refused.shots == 0;
}

test "duplicate and conflicting command ids stay single" {
    invite = "room-dup";
    directory = _dir();
    table = open_table(invite, directory);
    _seat(table, "player-a", invite);
    _seat(table, "player-b", invite);
    first = submit(table, "player-a", invite, "cmd-1", "A", 0, 0, "flare", 0.4, 5.0);
    assert first.ok;
    assert first.turn == 1;
    assert first.shots == 1;
    duplicate = submit(table, "player-a", invite, "cmd-1", "A", 0, 0, "flare", 0.4, 5.0);
    assert duplicate.ok;
    assert duplicate.turn == 1;
    assert duplicate.shots == 1;
    conflict = submit(table, "player-a", invite, "cmd-1", "A", 0, 0, "flare", 0.5, 5.0);
    assert not conflict.ok;
    assert conflict.code == "conflict";
    assert conflict.shots == 1;
}

test "stale revision, busy flag, and a finished table are rejected" {
    invite = "room-stale";
    directory = _dir();
    table = open_table(invite, directory);
    _seat(table, "player-a", invite);
    _seat(table, "player-b", invite);
    table.in_flight = True;
    busy = submit(table, "player-a", invite, "cmd-busy", "A", 0, 0, "flare", 0.4, 5.0);
    assert busy.code == "busy";
    assert busy.shots == 0;
    table.in_flight = False;
    accepted = submit(table, "player-a", invite, "cmd-a", "A", 0, 0, "flare", 0.4, 5.0);
    assert accepted.ok;
    stale = submit(table, "player-b", invite, "cmd-b", "B", 0, 1, "flare", 2.7, 5.0);
    assert not stale.ok;
    assert stale.code == "revision";
    current = submit(table, "player-b", invite, "cmd-b", "B", 1, 1, "flare", 2.7, 5.0);
    assert current.ok;
    assert current.turn == 2;
    table.force_finished = True;
    done = submit(table, "player-a", invite, "cmd-c", "A", 2, 2, "shell", 0.4, 5.0);
    assert done.code == "finished";
    assert done.shots == 2;
}

test "reload drops an uncommitted shot and does not repeat a committed one" {
    invite = "room-restart";
    directory = _dir();
    table = open_table(invite, directory);
    _seat(table, "player-a", invite);
    _seat(table, "player-b", invite);
    table.fail_before_commit = True;
    interrupted = submit(table, "player-a", invite, "cmd-lost", "A", 0, 0, "flare", 0.4, 5.0);
    assert interrupted.code == "interrupted";
    assert interrupted.shots == 0;
    restored = reload_table(invite, directory);
    assert restored.shots == 0;
    assert restored.turn == 0;
    committed = submit(restored, "player-a", invite, "cmd-lost", "A", 0, 0, "flare", 0.4, 5.0);
    assert committed.ok;
    assert committed.shots == 1;
    assert committed.turn == 1;
    restarted = reload_table(invite, directory);
    assert restarted.shots == 1;
    assert restarted.turn == 1;
    retry = submit(restarted, "player-a", invite, "cmd-lost", "A", 0, 0, "flare", 0.4, 5.0);
    assert retry.ok;
    assert retry.shots == 1;
    assert retry.turn == 1;
}

test "the journal and the seat view omit the sentinel" {
    invite = "room-hidden";
    directory = _dir();
    table = open_table(invite, directory);
    table.secrets.append(SecretBody(
        id="sentinel",
        owner="B",
        x=12345.67,
        y=-9876.54,
        w=1.0,
        h=1.0,
        angle=0.2,
        role="objective",
        alive=True,
        health=9.0
    ));
    _seat(table, "player-a", invite);
    _seat(table, "player-b", invite);
    seen = look(table, "player-a");
    assert "12345.67" not in seen;
    assert "-9876.54" not in seen;
    submit(table, "player-a", invite, "cmd-hide", "A", 0, 0, "flare", 0.4, 5.0);
    raw = Path(directory + "/journal.jsonl").read_text();
    assert "12345.67" not in raw;
    assert "-9876.54" not in raw;
    parsed = json.loads(raw.split("\n")[0]);
    assert parsed["shots"] == 1;
}
