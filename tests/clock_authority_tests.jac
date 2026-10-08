"""Reveal authorization uses the server clock. Client now_ms cannot extend or reopen it."""

import json;
import tempfile;
import from server.clock { pin_clock }
import from server.live { boot_match, claim_player, take_shot, watch }

def _dir() -> str {
    return tempfile.mkdtemp(prefix="fogshot-clock-");
}

def _ready(directory: str) -> any {
    live = boot_match(directory);
    claim_player(live, "player-a");
    claim_player(live, "player-b");
    return live;
}

def _has_id(bodies: list[any], body_id: str) -> bool {
    if bodies is None {
        return False;
    }
    for body in bodies {
        if body["id"] == body_id {
            return True;
        }
    }
    return False;
}

test "client time cannot extend or reopen a reveal" {
    directory = _dir();
    live = _ready(directory);
    pin_clock(10000);
    flare_a = json.loads(take_shot(live, "player-a", "flare-a", 20.0, 300.0, 800.0, 400.0, 1.0, live.table.epoch, live.table.turn, live.table.revision, "flare"));
    assert flare_a["ok"];
    assert flare_a["reveal_until"] == 13000;
    pin_clock(20000);
    flare_b = json.loads(take_shot(live, "player-b", "flare-b", 60.0, 300.0, 800.0, 400.0, 1.0, live.table.epoch, live.table.turn, live.table.revision, "flare"));
    assert flare_b["ok"];
    # B's short flare misses the post and scouts the ground. The deadline is the server clock.
    assert flare_b["reveal_until"] == 23000;
    assert flare_b["view"]["reveal"] is not None;
    assert "core-a" not in json.dumps(flare_b);
    assert "4.25" not in json.dumps(flare_b);
    pin_clock(30000);
    opened = json.loads(take_shot(live, "player-a", "shell-a", 20.0, 300.0, 800.0, 400.0, 1.0, live.table.epoch, live.table.turn, live.table.revision, "shell"));
    assert opened["ok"];
    assert opened["reveal_until"] == 33000;
    assert opened["view"]["reveal"] is not None;
    pin_clock(36000);
    stale = json.loads(watch(live, "player-a", 0));
    future = json.loads(watch(live, "player-a", 9000000000000));
    omitted = json.loads(watch(live, "player-a", 30000));
    assert stale["view"]["reveal"] is None;
    assert future["view"]["reveal"] is None;
    assert omitted["view"]["reveal"] is None;
    assert "enemy-post" not in json.dumps(stale);
    retry = json.loads(take_shot(live, "player-a", "shell-a", 20.0, 300.0, 800.0, 400.0, 1.0, live.table.epoch, live.table.turn, live.table.revision, "shell"));
    assert retry["ok"];
    assert retry["view"]["reveal"] is None;
    rejoined = boot_match(directory);
    claim_player(rejoined, "player-a");
    again = json.loads(watch(rejoined, "player-a", 0));
    assert again["view"]["reveal"] is None;
    assert "enemy-post" not in json.dumps(again);
}

test "an open reveal does not publish an out-of-patch post" {
    directory = _dir();
    live = _ready(directory);
    pin_clock(10000);
    take_shot(live, "player-a", "flare-a", 20.0, 300.0, 800.0, 400.0, 1.0, live.table.epoch, live.table.turn, live.table.revision, "flare");
    pin_clock(20000);
    take_shot(live, "player-b", "flare-b", 60.0, 300.0, 800.0, 400.0, 1.0, live.table.epoch, live.table.turn, live.table.revision, "flare");
    pin_clock(30000);
    broken = json.loads(take_shot(live, "player-a", "shell-link", 20.0, 300.0, 800.0, 400.0, 1.0, live.table.epoch, live.table.turn, live.table.revision, "shell"));
    assert broken["broken"];
    pin_clock(40000);
    take_shot(live, "player-b", "shell-b", 60.0, 300.0, 800.0, 400.0, 1.0, live.table.epoch, live.table.turn, live.table.revision, "shell");
    pin_clock(50000);
    finish = json.loads(take_shot(live, "player-a", "shell-core", 10.0, 390.0, 800.0, 400.0, 1.0, live.table.epoch, live.table.turn, live.table.revision, "shell"));
    assert finish["ok"];
    assert finish["result"] == "A";
    assert finish["view"]["reveal"] is not None;
    assert not _has_id(finish["view"]["reveal"]["bodies"], "enemy-post");
    assert finish["broken"] == False;
    assert finish["angle"] == 0.0;
    assert "enemy-post" not in json.dumps(finish);
}
