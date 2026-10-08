"""Each room is its own match. A quiet seat comes free. Another room does not move."""

import json;
import from server.authority { claim, note_seen, release_player, release_stale }
import from server.live { open_room, room_match, take_shot }

test "a shot in one room does not move the other room" {
    left = open_room();
    right = open_room();
    assert left != right;
    assert left != "fogshot";
    assert len(left) == 6;
    match_left = room_match(left);
    match_right = room_match(right);
    assert match_left.table.invite == left;
    assert match_right.table.invite == right;
    seated_left = claim(match_left.table, "player-a", left);
    seated_right = claim(match_right.table, "player-b", right);
    held = claim(match_right.table, "player-c", right);
    assert seated_left.ok and seated_left.seat == "A";
    assert seated_right.ok and seated_right.seat == "A";
    assert held.ok and held.seat == "B";
    note_seen(match_left.table, "player-a", 1000);
    note_seen(match_right.table, "player-b", 5000);
    note_seen(match_right.table, "player-c", 5000);
    fired = json.loads(take_shot(
        match_left, "player-a", "flare-left", 20.0, 300.0, 800.0, 400.0, 1.0,
        match_left.table.epoch, match_left.table.turn, match_left.table.revision, "flare"
    ));
    assert fired["ok"];
    assert match_left.table.turn == 1;
    assert match_right.table.turn == 0;
    assert match_right.table.shots == 0;
    assert match_right.table.rules.phase == "recon";
    assert room_match("fogshot") is None;
    assert room_match("../secret") is None;
    assert release_stale(match_left.table, 1000 + 30001);
    assert match_left.table.seat_a == "";
    assert match_right.table.seat_a == "player-b";
    assert match_right.table.seat_b == "player-c";
    assert not release_stale(match_right.table, 5000 + 30000);
    assert release_player(match_right.table, "player-b");
    assert match_right.table.seat_a == "";
    assert match_right.table.seat_b == "player-c";
}
