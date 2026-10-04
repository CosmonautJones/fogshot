"""Both outposts can be cut. A falling support crushes a neighbor once. Supply adds one perk."""

import json;
import tempfile;
import from graph.supply { Cable, Site }
import from server.live { boot_match, claim_player, take_shot, watch }

def _dir() -> str {
    return tempfile.mkdtemp(prefix="fogshot-outpost-");
}

def _pull(live: any, player: str, command_id: str, x: float, y: float, weapon: str) -> any {
    return json.loads(take_shot(
        live, player, command_id, x, y, 800.0, 400.0, 1.0,
        live.table.epoch, live.table.turn, live.table.revision, weapon
    ));
}

def _open(live: any) -> None {
    _pull(live, "player-a", "flare-a", 20.0, 300.0, "flare");
    _pull(live, "player-b", "flare-b", 60.0, 300.0, "flare");
}

test "a falling support crushes a neighbor the shell did not hit" {
    directory = _dir();
    live = boot_match(directory);
    claim_player(live, "player-a");
    claim_player(live, "player-b");
    _open(live);
    shell = _pull(live, "player-a", "shell-a", 20.0, 300.0, "shell");
    assert shell["ok"];
    assert shell["broken"];
    assert shell["reveal_radius"] == 2.6;
    assert shell["perk"] == "scout";
    spur = live.world.find("spur-b");
    assert spur is not None;
    assert spur.broken;
    assert spur.applications == 1;
    assert "shot|spur-b" not in live.world.pairs;
    post_a = live.world.find("post-a");
    assert post_a is not None;
    assert not post_a.broken;
    other = _pull(live, "player-b", "shell-b", 20.0, 300.0, "shell");
    assert other["ok"];
    assert other["shot_ready"];
    assert other["reveal_radius"] == 2.2;
    assert other["perk"] == "";
    assert post_a.broken;
    home = json.loads(watch(live, "player-a", 0));
    assert home["own_powered"] == False;
    assert home["shot_ready"];
    assert "12345.67" not in json.dumps(other);
    assert "4.25" not in json.dumps(other);
}

test "an alternate cable keeps the perk after the post falls" {
    directory = _dir();
    live = boot_match(directory);
    claim_player(live, "player-a");
    claim_player(live, "player-b");
    source = live.source_b as Site;
    core = live.core_node_b as Site;
    bypass = Site(name="bypass-b", owner="B", kind="link", intact=True);
    source +>:Cable():+> bypass;
    bypass +>:Cable():+> core;
    _open(live);
    _pull(live, "player-a", "shell-a", 20.0, 300.0, "shell");
    owner = json.loads(watch(live, "player-b", 0));
    assert owner["own_powered"];
    assert owner["shot_ready"];
    assert owner["perk"] == "scout";
}
