"""Supply loss leaves the shell available. A dead core ends the match. Rematch restores it."""

import json;
import tempfile;
import from server.clock { pin_clock }
import from server.live { boot_match, claim_player, rematch_room, take_shot, watch }

def _dir() -> str {
    return tempfile.mkdtemp(prefix="fogshot-outcome-");
}

test "a dark supply still allows a shell, then the core decides the winner" {
    directory = _dir();
    live = boot_match(directory);
    seat_a = claim_player(live, "player-a");
    seat_b = claim_player(live, "player-b");
    assert seat_a.seat == "A";
    assert seat_b.seat == "B";
    take_shot(live, "player-a", "flare-a", 20.0, 300.0, 800.0, 400.0, 1.0, 1000);
    take_shot(live, "player-b", "flare-b", 60.0, 300.0, 800.0, 400.0, 1.0, 2000);
    opened = take_shot(live, "player-a", "shell-link", 20.0, 300.0, 800.0, 400.0, 1.0, 5000);
    link = json.loads(opened);
    assert link["ok"];
    assert link["broken"];
    assert link["result"] == "";
    assert link["phase"] == "combat";
    assert "core-b" not in opened;
    assert '"id": "core-a"' in opened;
    assert "12345.67" not in opened;
    assert "-9876.54" not in opened;
    owner = json.loads(watch(live, "player-b", 5000));
    assert owner["own_powered"] == False;
    assert owner["shot_ready"] == True;
    assert owner["own_core"] == True;
    assert owner["result"] == "";
    assert owner["enemy_cores"] == 1;
    carried = take_shot(live, "player-b", "shell-b", 60.0, 300.0, 800.0, 400.0, 1.0, 6000);
    still = json.loads(carried);
    assert still["ok"];
    assert still["result"] == "";
    assert still["shot_ready"] == True;
    assert "4.25" not in carried;
    assert "12345.67" not in carried;
    assert "-9876.54" not in carried;
    assert "87654.32" not in carried;
    finish = take_shot(live, "player-a", "shell-core", 10.0, 390.0, 800.0, 400.0, 1.0, 9000);
    won = json.loads(finish);
    assert won["ok"];
    assert won["result"] == "A";
    assert won["phase"] == "finished";
    assert won["shot_ready"] == False;
    assert "12345.67" not in finish;
    assert "-9876.54" not in finish;
    denied = json.loads(take_shot(live, "player-b", "shell-late", 60.0, 300.0, 800.0, 400.0, 1.0, 12000));
    assert denied["code"] == "finished";
    pin_clock(won["reveal_until"] + 1);
    closed = watch(live, "player-a", 0);
    assert "core-b" not in closed;
    assert "12345.67" not in closed;
    hidden = watch(live, "player-b", 12000);
    assert "4.25" not in hidden;
    assert "12345.67" not in hidden;
    assert "-9876.54" not in hidden;
    assert "87654.32" not in hidden;
    again = json.loads(rematch_room(live, "player-b"));
    assert again["ok"];
    assert again["phase"] == "recon";
    assert again["result"] == "";
    assert again["own_powered"] == True;
    assert again["own_core"] == True;
    assert again["shot_ready"] == True;
    assert "12345.67" not in json.dumps(again);
}
