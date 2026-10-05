"""The canvas pull is one Pymunk shot on a shared match. Unrevealed coordinates stay out of the wire."""

import json;
import tempfile;
import from server.clock { pin_clock }
import from server.live { boot_match, claim_player, take_shot, watch }

def _dir() -> str {
    return tempfile.mkdtemp(prefix="fogshot-live-");
}

def _max_x(path: list[any]) -> float {
    best = 0.0;
    for point in path {
        if point[0] > best {
            best = point[0];
        }
    }
    return best;
}

def _has_id(bodies: list[any], body_id: str) -> bool {
    for body in bodies {
        if body["id"] == body_id {
            return True;
        }
    }
    return False;
}

test "a canvas shell crosses the fog, collapses the post, and the reveal closes" {
    directory = _dir();
    live = boot_match(directory);
    seat_a = claim_player(live, "player-a");
    seat_b = claim_player(live, "player-b");
    assert seat_a.ok and seat_a.seat == "A";
    assert seat_b.ok and seat_b.seat == "B";
    flare_raw = take_shot(live, "player-a", "flare-a", 20.0, 300.0, 800.0, 400.0, 1.0, live.table.epoch, live.table.turn, live.table.revision, "flare");
    flare = json.loads(flare_raw);
    assert flare["ok"];
    assert flare["weapon"] == "flare";
    assert not flare["broken"];
    assert flare["angle"] < 0.4;
    assert _max_x(flare["path"]) > 20.0;
    assert "12345.67" not in flare_raw;
    assert "-9876.54" not in flare_raw;
    assert "87654.32" not in flare_raw;
    assert "far-a" not in flare_raw;
    other = take_shot(live, "player-b", "flare-b", 60.0, 300.0, 800.0, 400.0, 1.0, live.table.epoch, live.table.turn, live.table.revision, "flare");
    other_row = json.loads(other);
    assert other_row["ok"];
    assert other_row["weapon"] == "flare";
    assert "12345.67" not in other;
    assert "-9876.54" not in other;
    assert "87654.32" not in other;
    shell_raw = take_shot(live, "player-a", "shell-a", 20.0, 300.0, 800.0, 400.0, 1.0, live.table.epoch, live.table.turn, live.table.revision, "shell");
    shell = json.loads(shell_raw);
    assert shell["ok"];
    assert shell["weapon"] == "shell";
    assert shell["broken"];
    assert shell["angle"] > 0.7;
    assert _max_x(shell["path"]) > 20.0;
    assert shell["view"]["reveal"] is not None;
    assert _has_id(shell["view"]["reveal"]["bodies"], "enemy-post");
    assert "12345.67" not in shell_raw;
    assert "-9876.54" not in shell_raw;
    pin_clock(shell["reveal_until"] + 1);
    closed = watch(live, "player-a", 0);
    assert "enemy-post" not in closed;
    assert "12345.67" not in closed;
    assert "-9876.54" not in closed;
    hidden = watch(live, "player-b", 5000);
    assert "12345.67" not in hidden;
    assert "-9876.54" not in hidden;
    assert "87654.32" not in hidden;
    assert "enemy-post" in hidden;
}
