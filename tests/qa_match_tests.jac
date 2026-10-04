"""Live-match QA. Illegal shots, a miss, restart, and rematch go through Jac."""

import json;
import tempfile;
import from server.authority { submit }
import from server.clock { pin_clock }
import from server.live { boot_match, claim_player, rematch_room, take_shot, watch }

def _dir() -> str {
    return tempfile.mkdtemp(prefix="fogshot-qa-");
}

def _ready(directory: str) -> any {
    live = boot_match(directory);
    claim_player(live, "player-a");
    claim_player(live, "player-b");
    return live;
}

test "a wrong seat, a duplicate, a stale revision, and the wrong weapon do not shoot" {
    directory = _dir();
    live = _ready(directory);
    early = json.loads(take_shot(live, "player-b", "too-soon", 60.0, 300.0, 800.0, 400.0, 1.0, 1000));
    assert not early["ok"];
    assert early["code"] == "actor";
    assert early["phase"] == "recon";
    assert "4.25" not in json.dumps(early);
    assert "12345.67" not in json.dumps(early);
    guest = take_shot(live, "nobody", "guest", 20.0, 300.0, 800.0, 400.0, 1.0, 1000);
    assert json.loads(guest)["code"] == "unauthenticated";
    assert "core-a" not in guest;
    assert "core-b" not in guest;
    assert "4.25" not in guest;
    assert "12345.67" not in guest;
    shell_now = submit(live.table, "player-a", "fogshot", "cmd-shell", "A", 0, 0, "shell", 0.0, 5.0);
    assert shell_now.code == "weapon";
    assert shell_now.shots == 0;
    flare = json.loads(take_shot(live, "player-a", "flare-a", 20.0, 300.0, 800.0, 400.0, 1.0, 1000));
    assert flare["ok"];
    assert flare["weapon"] == "flare";
    assert not flare["broken"];
    duplicate = json.loads(take_shot(live, "player-a", "flare-a", 20.0, 300.0, 800.0, 400.0, 1.0, 1100));
    assert duplicate["ok"];
    assert duplicate["code"] == "";
    assert len(duplicate["path"]) == 0;
    clash = json.loads(take_shot(live, "player-a", "flare-a", 100.0, 390.0, 800.0, 400.0, 1.0, 1200));
    assert not clash["ok"];
    assert clash["code"] == "conflict";
    wrong_weapon = submit(
        live.table, "player-b", "fogshot", "cmd-shell-b", "B",
        live.table.revision, live.table.turn, "shell", 3.14, 3.0
    );
    assert wrong_weapon.code == "weapon";
    assert wrong_weapon.shots == 1;
    other = json.loads(take_shot(live, "player-b", "flare-b", 60.0, 300.0, 800.0, 400.0, 1.0, 2000));
    assert other["ok"];
    assert other["weapon"] == "flare";
    assert other["phase"] == "combat";
    stale = submit(
        live.table, "player-a", "fogshot", "cmd-stale", "A",
        0, live.table.turn, "shell", 0.0, 5.0
    );
    assert stale.code == "revision";
    assert stale.shots == 2;
    flare_late = submit(
        live.table, "player-a", "fogshot", "cmd-flare-late", "A",
        live.table.revision, live.table.turn, "flare", 0.0, 5.0
    );
    assert flare_late.code == "weapon";
    assert flare_late.shots == 2;
}

test "a miss still returns the projectile path and hides the enemy core" {
    directory = _dir();
    live = _ready(directory);
    flare = json.loads(take_shot(live, "player-a", "flare-a", 20.0, 300.0, 800.0, 400.0, 1.0, 1000));
    take_shot(live, "player-b", "flare-b", 60.0, 300.0, 800.0, 400.0, 1.0, 2000);
    pin_clock(flare["reveal_until"] + 1);
    missed_raw = take_shot(live, "player-a", "shell-miss", 100.0, 390.0, 800.0, 400.0, 1.0, 8000);
    missed = json.loads(missed_raw);
    assert missed["ok"];
    assert missed["code"] == "";
    assert missed["weapon"] == "shell";
    assert missed["phase"] == "combat";
    assert missed["result"] == "";
    assert not missed["broken"];
    assert len(missed["path"]) > 3;
    assert missed["view"]["reveal"] is None;
    assert "enemy-post" not in missed_raw;
    assert "core-b" not in missed_raw;
    assert "12345.67" not in missed_raw;
    hidden = watch(live, "player-b", 8000);
    assert "core-a" not in hidden;
    assert "4.25" not in hidden;
    assert "12345.67" not in hidden;
    assert "-9876.54" not in hidden;
    assert "87654.32" not in hidden;
    assert json.loads(hidden)["own_powered"];
    assert json.loads(hidden)["shot_ready"];
}

test "restart keeps both seats, the dark supply, the dead core, and rematch" {
    directory = _dir();
    live = _ready(directory);
    take_shot(live, "player-a", "flare-a", 20.0, 300.0, 800.0, 400.0, 1.0, 1000);
    take_shot(live, "player-b", "flare-b", 60.0, 300.0, 800.0, 400.0, 1.0, 2000);
    opened = json.loads(take_shot(live, "player-a", "shell-link", 20.0, 300.0, 800.0, 400.0, 1.0, 5000));
    assert opened["ok"];
    assert opened["broken"];
    assert opened["result"] == "";
    resumed = boot_match(directory);
    intruder = claim_player(resumed, "player-c");
    assert not intruder.ok;
    assert intruder.code == "full";
    assert claim_player(resumed, "player-a").seat == "A";
    assert claim_player(resumed, "player-b").seat == "B";
    owner = json.loads(watch(resumed, "player-b", 5000));
    assert owner["phase"] == "combat";
    assert owner["own_powered"] == False;
    assert owner["shot_ready"];
    assert owner["own_core"];
    assert owner["result"] == "";
    assert owner["broken"];
    assert "4.25" not in json.dumps(owner);
    assert "core-a" not in json.dumps(owner);
    assert "12345.67" not in json.dumps(owner);
    carried = json.loads(take_shot(resumed, "player-b", "shell-b", 60.0, 300.0, 800.0, 400.0, 1.0, 6000));
    assert carried["ok"];
    assert carried["result"] == "";
    assert carried["shot_ready"];
    assert "4.25" not in json.dumps(carried);
    finish = json.loads(take_shot(resumed, "player-a", "shell-core", 10.0, 390.0, 800.0, 400.0, 1.0, 9000));
    assert finish["ok"];
    assert finish["result"] == "A";
    assert finish["phase"] == "finished";
    denied = json.loads(take_shot(resumed, "player-b", "shell-late", 60.0, 300.0, 800.0, 400.0, 1.0, 12000));
    assert denied["code"] == "finished";
    pin_clock(finish["reveal_until"] + 1);
    closed = watch(resumed, "player-a", 0);
    assert "core-b" not in closed;
    restarted = boot_match(directory);
    assert claim_player(restarted, "player-c").code == "full";
    restored_b = json.loads(watch(restarted, "player-b", 13000));
    restored_a = json.loads(watch(restarted, "player-a", 13000));
    assert restored_b["phase"] == "finished";
    assert restored_b["result"] == "A";
    assert restored_b["own_core"] == False;
    assert restored_b["shot_ready"] == False;
    assert restored_a["enemy_cores"] == 0;
    assert "4.25" not in json.dumps(restored_b);
    assert "core-a" not in json.dumps(restored_b);
    assert "12345.67" not in json.dumps(restored_b);
    assert "87654.32" not in json.dumps(restored_b);
    again = json.loads(rematch_room(restarted, "player-a"));
    assert again["ok"];
    assert again["seat"] == "A";
    assert again["phase"] == "recon";
    assert again["own_powered"];
    other = json.loads(watch(restarted, "player-b", 0));
    assert other["seat"] == "B";
    assert other["phase"] == "recon";
    assert other["result"] == "";
    assert other["own_powered"];
    assert other["own_core"];
    assert other["shot_ready"];
    assert "4.25" not in json.dumps(other);
    fresh = boot_match(directory);
    assert claim_player(fresh, "player-c").code == "full";
    assert claim_player(fresh, "player-a").seat == "A";
    assert claim_player(fresh, "player-b").seat == "B";
    clean = json.loads(watch(fresh, "player-b", 0));
    assert clean["phase"] == "recon";
    assert clean["result"] == "";
    assert clean["own_powered"];
    assert clean["own_core"];
    assert not clean["broken"];
}
