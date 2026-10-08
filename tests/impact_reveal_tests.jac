"""The first impact opens the reveal, including a miss on empty ground."""

import json;
import tempfile;
import from server.clock { pin_clock }
import from server.live { boot_match, claim_player, take_shot }

def _dir() -> str {
    return tempfile.mkdtemp(prefix="fogshot-impact-");
}

def _pull(live: any, player: str, command_id: str, x: float, y: float, weapon: str) -> any {
    return json.loads(take_shot(
        live, player, command_id, x, y, 800.0, 400.0, 1.0,
        live.table.epoch, live.table.turn, live.table.revision, weapon
    ));
}

test "a shell miss and a flare both reveal the first impact" {
    directory = _dir();
    live = boot_match(directory);
    claim_player(live, "player-a");
    claim_player(live, "player-b");
    pin_clock(10000);
    flare = _pull(live, "player-a", "flare-miss", 100.0, 390.0, "flare");
    assert flare["ok"];
    assert flare["weapon"] == "flare";
    assert not flare["broken"];
    assert flare["view"]["reveal"] is not None;
    assert flare["reveal_radius"] == 3.0;
    assert "core-b" not in json.dumps(flare);
    assert "12345.67" not in json.dumps(flare);
    pin_clock(20000);
    other = _pull(live, "player-b", "flare-b", 60.0, 300.0, "flare");
    assert other["ok"];
    pin_clock(30000);
    missed = _pull(live, "player-a", "shell-miss", 100.0, 390.0, "shell");
    assert missed["ok"];
    assert missed["weapon"] == "shell";
    assert not missed["broken"];
    assert missed["view"]["reveal"] is not None;
    assert missed["reveal_radius"] == 2.6;
    assert missed["reveal_x"] > 5.0;
    assert missed["reveal_x"] < 12.0;
    assert "core-b" not in json.dumps(missed);
    assert "enemy-post" not in json.dumps(missed);
    assert "12345.67" not in json.dumps(missed);
}
