"""Seat B can end the match. The lob is a canvas pull, not a scripted rules result."""

import json;
import tempfile;
import from server.clock { pin_clock }
import from server.live { boot_match, claim_player, rematch_room, take_shot, watch }

def _dir() -> str {
    return tempfile.mkdtemp(prefix="fogshot-bwin-");
}

def _pull(live: any, player: str, command_id: str, x: float, y: float, weapon: str) -> str {
    return take_shot(
        live, player, command_id, x, y, 800.0, 400.0, 1.0,
        live.table.epoch, live.table.turn, live.table.revision, weapon
    );
}

test "seat B's lob destroys the enemy core and rematch clears it" {
    directory = _dir();
    live = boot_match(directory);
    claim_player(live, "player-a");
    claim_player(live, "player-b");
    _pull(live, "player-a", "flare-a", 20.0, 300.0, "flare");
    _pull(live, "player-b", "flare-b", 60.0, 300.0, "flare");
    opened = json.loads(_pull(live, "player-a", "shell-a", 20.0, 300.0, "shell"));
    assert opened["ok"];
    assert opened["result"] == "";
    quiet = watch(live, "player-b", 0);
    assert "30.61" not in quiet;
    assert "core-a" not in quiet;
    finish = json.loads(_pull(live, "player-b", "shell-core", 20.0, 390.0, "shell"));
    assert finish["ok"];
    assert finish["result"] == "B";
    assert finish["phase"] == "finished";
    assert finish["shot_ready"] == False;
    pin_clock(int(finish["reveal_until"]) + 1);
    closed = watch(live, "player-b", 0);
    assert "core-a" not in closed;
    assert "30.61" not in closed;
    other = json.loads(watch(live, "player-a", 0));
    assert other["result"] == "B";
    assert other["phase"] == "finished";
    again = json.loads(rematch_room(live, "player-a"));
    assert again["phase"] == "recon";
    assert again["result"] == "";
    assert again["epoch"] == 2;
    assert again["own_core"] == True;
}
