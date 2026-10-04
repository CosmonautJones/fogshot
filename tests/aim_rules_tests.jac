"""Pull-back conversion and pure turn rules. No physics and no hidden query."""

import math;
import from game.aim { release_pull, short_guide }
import from game.rules { MatchRules, accept_shot, resolve_cores }

test "cancelled drag does not fire" {
    aim = release_pull("A", 60.0, 300.0, 800.0, 400.0, 1.0, False, True, False);
    assert not aim.fired;
    assert aim.reason == "cancelled";
}

test "a second pointer does not fire" {
    aim = release_pull("A", 60.0, 300.0, 800.0, 400.0, 1.0, True, False, True);
    assert not aim.fired;
    assert aim.reason == "duplicate";
}

test "resize keeps the same world pull" {
    small = release_pull("A", 60.0, 300.0, 800.0, 400.0, 1.0, True, False, False);
    large = release_pull("A", 120.0, 600.0, 1600.0, 800.0, 1.0, True, False, False);
    assert small.fired and large.fired;
    assert abs(small.angle - large.angle) < 0.0001;
    assert abs(small.power - large.power) < 0.0001;
}

test "device pixels follow the device pixel ratio" {
    css = release_pull("A", 60.0, 300.0, 800.0, 400.0, 1.0, True, False, False);
    device = release_pull("A", 120.0, 600.0, 800.0, 400.0, 2.0, True, False, False);
    assert css.fired and device.fired;
    assert abs(css.angle - device.angle) < 0.0001;
    assert abs(css.power - device.power) < 0.0001;
}

test "mirrored seat aims back across the valley" {
    aim = release_pull("B", 60.0, 300.0, 800.0, 400.0, 1.0, True, False, False);
    assert aim.fired, aim.reason;
    assert math.cos(aim.angle) < -0.5, "seat B did not aim toward decreasing x";
}

test "nonfinite pointer does not fire" {
    aim = release_pull("A", math.nan, 300.0, 800.0, 400.0, 1.0, True, False, False);
    assert not aim.fired;
    assert aim.reason == "nonfinite";
}

test "guide stays short and on the friendly side" {
    points = short_guide("A", 0.4, 12.0);
    assert len(points) >= 2;
    assert len(points) <= 8;
    for point in points {
        assert point[0] < 20.0, "guide crossed into the hidden half";
    }
}

test "wrong actor turn and revision are rejected" {
    rules = MatchRules();
    wrong_actor = accept_shot(rules, "B", 0, 0, "flare", 0.4, 10.0);
    assert not wrong_actor.ok;
    assert wrong_actor.code == "actor";
    wrong_turn = accept_shot(rules, "A", 0, 4, "flare", 0.4, 10.0);
    assert not wrong_turn.ok;
    assert wrong_turn.code == "turn";
    wrong_rev = accept_shot(rules, "A", 3, 0, "flare", 0.4, 10.0);
    assert not wrong_rev.ok;
    assert wrong_rev.code == "revision";
}

test "recon accepts only that seat's flare" {
    rules = MatchRules();
    shell = accept_shot(rules, "A", 0, 0, "shell", 0.4, 10.0);
    assert not shell.ok;
    assert shell.code == "weapon";
    opened = accept_shot(rules, "A", 0, 0, "flare", 0.4, 10.0);
    assert opened.ok;
    assert opened.state.phase == "recon";
    assert opened.state.active == "B";
    early_shell = accept_shot(opened.state, "B", opened.state.revision, opened.state.turn, "shell", math.pi, 10.0);
    assert not early_shell.ok;
    both = accept_shot(opened.state, "B", opened.state.revision, opened.state.turn, "flare", math.pi, 10.0);
    assert both.ok;
    assert both.state.phase == "combat";
    assert both.state.active == "A";
}

test "combat rejects a flare and a finished match" {
    rules = MatchRules();
    first = accept_shot(rules, "A", 0, 0, "flare", 0.4, 10.0);
    second = accept_shot(first.state, "B", first.state.revision, first.state.turn, "flare", math.pi, 10.0);
    flare = accept_shot(second.state, "A", second.state.revision, second.state.turn, "flare", 0.4, 10.0);
    assert not flare.ok;
    assert flare.code == "weapon";
    shell = accept_shot(second.state, "A", second.state.revision, second.state.turn, "shell", 0.4, 10.0);
    assert shell.ok;
    assert shell.state.active == "B";
    done = resolve_cores(shell.state, False, True);
    assert done.result == "B";
    assert done.phase == "finished";
    late = accept_shot(done, "B", done.revision, done.turn, "shell", 0.4, 10.0);
    assert not late.ok;
    assert late.code == "finished";
}

test "simultaneous elimination is a draw" {
    rules = MatchRules();
    done = resolve_cores(rules, False, False);
    assert done.result == "draw";
    assert done.phase == "finished";
}
