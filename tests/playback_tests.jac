"""Both seats receive a timed, filtered shot. The other seat does not see the approach."""

import json;
import tempfile;
import from server.clock { pin_clock }
import from server.live { boot_match, claim_player, take_shot, watch }

def _dir() -> str {
    return tempfile.mkdtemp(prefix="fogshot-play-");
}

def _times_hold(path: list[any]) -> bool {
    previous = -1.0;
    for point in path {
        if len(point) != 3 {
            return False;
        }
        if point[2] < previous {
            return False;
        }
        previous = point[2];
    }
    return len(path) > 0;
}

def _has_x_below(path: list[any], limit: float) -> bool {
    for point in path {
        if point[0] < limit {
            return True;
        }
    }
    return False;
}

test "the other seat sees the impact path and not the hidden approach" {
    directory = _dir();
    live = boot_match(directory);
    claim_player(live, "player-a");
    claim_player(live, "player-b");
    take_shot(live, "player-a", "flare-a", 20.0, 300.0, 800.0, 400.0, 1.0, live.table.epoch, live.table.turn, live.table.revision, "flare");
    take_shot(live, "player-b", "flare-b", 60.0, 300.0, 800.0, 400.0, 1.0, live.table.epoch, live.table.turn, live.table.revision, "flare");
    shell_raw = take_shot(live, "player-a", "shell-a", 20.0, 300.0, 800.0, 400.0, 1.0, live.table.epoch, live.table.turn, live.table.revision, "shell");
    shell = json.loads(shell_raw);
    assert shell["ok"];
    assert shell["broken"];
    watched_raw = watch(live, "player-b", 0);
    watched = json.loads(watched_raw);
    assert len(watched["path"]) > 3;
    assert not shell["your_turn"];
    assert _times_hold(watched["path"]);
    assert not _has_x_below(watched["path"], 16.0);
    assert _times_hold(shell["path"]);
    assert _has_x_below(shell["path"], 12.0);
    assert len(watched["path"]) <= 80;
    assert len(watched["collapse"]) > 1;
    last = len(watched["collapse"]) - 1;
    assert watched["collapse"][0][1] <= watched["collapse"][last][1];
    assert watched["collapse"][last][0] > 0.7;
    assert watched["your_turn"];
    resumed = boot_match(directory);
    restored = json.loads(watch(resumed, "player-b", 0));
    assert len(restored["path"]) > 3;
    assert not _has_x_below(restored["path"], 16.0);
    guest = json.loads(watch(live, "nobody", 0));
    assert len(guest["path"]) == 0;
    assert len(guest["collapse"]) == 0;
    assert "12345.67" not in watched_raw;
    assert "-9876.54" not in watched_raw;
    assert "87654.32" not in watched_raw;
    pin_clock(shell["reveal_until"] + 1);
    expired = json.loads(watch(live, "player-b", 0));
    assert len(expired["path"]) == 0;
    assert len(expired["collapse"]) == 0;
}
