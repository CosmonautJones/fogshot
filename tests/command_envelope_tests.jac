"""Command retries keep the original intent. Stale and old-epoch commands do not shoot."""

import json;
import tempfile;
import from server.live { boot_match, claim_player, rematch_room, take_shot }

def _dir() -> str {
    return tempfile.mkdtemp(prefix="fogshot-cmd-");
}

def _ready(directory: str) -> any {
    live = boot_match(directory);
    claim_player(live, "player-a");
    claim_player(live, "player-b");
    return live;
}

def _pull(live: any, player: str, command_id: str, x: float, y: float, epoch: int, turn: int, revision: int, weapon: str) -> any {
    return json.loads(take_shot(
        live, player, command_id, x, y, 800.0, 400.0, 1.0, epoch, turn, revision, weapon
    ));
}

test "an exact flare retry survives the change to combat" {
    directory = _dir();
    live = _ready(directory);
    first = _pull(live, "player-a", "flare-a", 20.0, 300.0, 1, 0, 0, "flare");
    assert first["ok"];
    assert first["weapon"] == "flare";
    assert live.table.shots == 1;
    second = _pull(live, "player-b", "flare-b", 60.0, 300.0, live.table.epoch, live.table.turn, live.table.revision, "flare");
    assert second["ok"];
    assert second["phase"] == "combat";
    shots = live.table.shots;
    retry = _pull(live, "player-a", "flare-a", 20.0, 300.0, 1, 0, 0, "flare");
    assert retry["ok"];
    assert retry["code"] == "";
    assert retry["weapon"] == "flare";
    assert len(retry["path"]) == 0;
    assert live.table.shots == shots;
}

test "a new command with an old revision does not shoot" {
    directory = _dir();
    live = _ready(directory);
    _pull(live, "player-a", "flare-a", 20.0, 300.0, 1, 0, 0, "flare");
    _pull(live, "player-b", "flare-b", 60.0, 300.0, live.table.epoch, live.table.turn, live.table.revision, "flare");
    assert live.table.rules.phase == "combat";
    assert live.table.rules.active == "A";
    shots = live.table.shots;
    stale = _pull(live, "player-a", "shell-late", 20.0, 300.0, live.table.epoch, live.table.turn, 0, "shell");
    assert not stale["ok"];
    assert stale["code"] == "revision";
    assert live.table.shots == shots;
}

test "a changed intent and an old epoch do not simulate" {
    directory = _dir();
    live = _ready(directory);
    _pull(live, "player-a", "flare-a", 20.0, 300.0, 1, 0, 0, "flare");
    shots = live.table.shots;
    clash = _pull(live, "player-a", "flare-a", 20.0, 300.0, 1, 0, 0, "shell");
    assert not clash["ok"];
    assert clash["code"] == "conflict";
    assert live.table.shots == shots;
    _pull(live, "player-b", "flare-b", 60.0, 300.0, live.table.epoch, live.table.turn, live.table.revision, "flare");
    _pull(live, "player-a", "shell-link", 20.0, 300.0, live.table.epoch, live.table.turn, live.table.revision, "shell");
    _pull(live, "player-b", "shell-b", 60.0, 300.0, live.table.epoch, live.table.turn, live.table.revision, "shell");
    won = _pull(live, "player-a", "shell-core", 10.0, 390.0, live.table.epoch, live.table.turn, live.table.revision, "shell");
    assert won["result"] == "A";
    again = json.loads(rematch_room(live, "player-a"));
    assert again["phase"] == "recon";
    assert again["epoch"] == 2;
    shots = live.table.shots;
    old = _pull(live, "player-a", "flare-a", 20.0, 300.0, 1, 0, 0, "flare");
    assert not old["ok"];
    assert old["code"] == "epoch";
    assert live.table.shots == shots;
    assert live.table.rules.phase == "recon";
    assert old["view"]["reveal"] is None;
}
