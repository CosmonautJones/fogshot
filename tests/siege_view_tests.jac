"""One trusted shot, one damage application, checkpoint restore, and private views."""

import json;
import from physics.siege { build_range, fire_shell, fire_flare }
import from server.views { SecretBody, project_view }

test "a shell topples the enemy post once" {
    world = build_range();
    outcome = fire_shell(world, 0.15, 14.0);
    assert outcome.steps == 1400;
    assert outcome.contacted("shell", "enemy-post");
    post = outcome.body("enemy-post");
    assert post.broken;
    assert abs(post.angle) > 0.7;
    assert post.applications == 1, "contact damage ran more than once";
}

test "a flare records the impact and does not break the post" {
    world = build_range();
    before = world.capture();
    outcome = fire_flare(world, 0.15, 14.0);
    assert outcome.contacted("flare", "enemy-post");
    post = outcome.body("enemy-post");
    assert not post.broken;
    assert abs(post.angle - before[0].angle) < 0.08;
}

test "restore puts the braced post back" {
    world = build_range();
    before = world.capture();
    fire_shell(world, 0.15, 14.0);
    assert world.capture()[0].broken;
    world.restore(before);
    restored = world.capture()[0];
    assert not restored.broken;
    assert abs(restored.angle - before[0].angle) < 0.02;
    assert abs(restored.x - before[0].x) < 0.05;
}

test "unrevealed sentinel coordinates stay out of the view" {
    hidden_mark = SecretBody(
        id="sentinel",
        owner="B",
        x=12345.67,
        y=-9876.54,
        w=1.0,
        h=1.0,
        angle=0.2,
        role="objective",
        alive=True,
        health=9.0
    );
    friendly = SecretBody(
        id="own-post",
        owner="A",
        x=8.0,
        y=2.0,
        w=0.2,
        h=3.0,
        angle=0.0,
        role="objective",
        alive=True,
        health=4.0
    );
    public_ground = SecretBody(
        id="ground",
        owner="public",
        x=20.0,
        y=0.0,
        w=40.0,
        h=0.2,
        angle=0.0,
        role="ground",
        alive=True,
        health=0.0
    );
    view = project_view("A", [friendly, hidden_mark, public_ground], 0.0, 0.0, 0.0, False, 0, 0);
    raw = json.dumps(view.__dict__);
    assert "12345.67" not in raw;
    assert "-9876.54" not in raw;
    assert "own-post" in raw;
    assert view.own[0].health == 4.0;
    assert view.reveal is None;
}

test "reveal includes only the patch and expires" {
    near = SecretBody(
        id="near",
        owner="B",
        x=24.0,
        y=2.0,
        w=0.2,
        h=3.0,
        angle=0.4,
        role="objective",
        alive=True,
        health=1.0
    );
    far = SecretBody(
        id="far",
        owner="B",
        x=30.0,
        y=2.0,
        w=0.2,
        h=3.0,
        angle=0.0,
        role="rubble",
        alive=True,
        health=1.0
    );
    wide = SecretBody(
        id="wide",
        owner="B",
        x=24.2,
        y=2.0,
        w=30.0,
        h=0.4,
        angle=0.0,
        role="beam",
        alive=True,
        health=1.0
    );
    shown = project_view("A", [near, far, wide], 24.0, 2.0, 2.5, True, 0, 3000);
    assert shown.reveal is not None;
    ids: list[str] = [];
    for body in shown.reveal.bodies {
        ids.append(body.id);
        assert body.health < 0.0;
    }
    assert "near" in ids;
    assert "far" not in ids;
    assert "wide" in ids;
    wide_body = shown.reveal.bodies[1] if shown.reveal.bodies[0].id == "near" else shown.reveal.bodies[0];
    assert wide_body.w < 5.0, "oversized beam was not clipped to the patch";
    expired = project_view("A", [near, far, wide], 24.0, 2.0, 2.5, True, 4000, 3000);
    raw = json.dumps(expired.__dict__);
    assert expired.reveal is None;
    assert "24.0" not in raw;
}
