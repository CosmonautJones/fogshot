"""A shot commits physics and the journal together. A failed write rolls both back."""

import json;
import tempfile;
import from server.live { boot_match, claim_player, take_shot }

def _dir() -> str {
    return tempfile.mkdtemp(prefix="fogshot-tx-");
}

def _ready(directory: str) -> any {
    live = boot_match(directory);
    claim_player(live, "player-a");
    claim_player(live, "player-b");
    return live;
}

def _pull(live: any, player: str, command_id: str, x: float, y: float, weapon: str) -> any {
    return json.loads(take_shot(
        live, player, command_id, x, y, 800.0, 400.0, 1.0,
        live.table.epoch, live.table.turn, live.table.revision, weapon
    ));
}

test "a simulation failure releases the match without a shot" {
    directory = _dir();
    live = _ready(directory);
    live.table.fail_simulate = True;
    failed = _pull(live, "player-a", "flare-a", 20.0, 300.0, "flare");
    assert not failed["ok"];
    assert failed["code"] == "interrupted";
    assert live.table.shots == 0;
    assert not live.table.in_flight;
    again = _pull(live, "player-a", "flare-a", 20.0, 300.0, "flare");
    assert again["ok"];
    assert live.table.shots == 1;
}

test "storage failure restores a destroyed core and the next shot can hit it" {
    directory = _dir();
    live = _ready(directory);
    assert _pull(live, "player-a", "flare-a", 20.0, 300.0, "flare")["ok"];
    assert _pull(live, "player-b", "flare-b", 60.0, 300.0, "flare")["ok"];
    assert _pull(live, "player-a", "shell-link", 20.0, 300.0, "shell")["ok"];
    assert _pull(live, "player-b", "shell-b", 60.0, 300.0, "shell")["ok"];
    shots = live.table.shots;
    live.table.fail_storage = True;
    failed = _pull(live, "player-a", "shell-core", 10.0, 390.0, "shell");
    assert not failed["ok"];
    assert failed["code"] == "interrupted";
    assert live.table.shots == shots;
    assert not live.table.in_flight;
    assert live.core_b_alive;
    resumed = boot_match(directory);
    assert resumed.core_b_alive;
    claim_player(resumed, "player-a");
    claim_player(resumed, "player-b");
    again = _pull(resumed, "player-a", "shell-core", 10.0, 390.0, "shell");
    assert again["ok"];
    assert again["result"] == "A";
    assert not resumed.core_b_alive;
    lost = boot_match(directory);
    assert not lost.core_b_alive;
    assert lost.table.rules.result == "A";
    claim_player(lost, "player-a");
    retry = _pull(lost, "player-a", "shell-core", 10.0, 390.0, "shell");
    assert retry["ok"];
    assert retry["code"] == "";
    assert lost.table.shots == resumed.table.shots;
}
