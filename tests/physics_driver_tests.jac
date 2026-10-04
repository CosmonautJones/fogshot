"""Server-side physics behavior. Pymunk is the solver; Jac owns the scenario."""

import from physics.pymunk_driver { PhysicsWorld }

test "projectile contacts a thin support" {
    world = PhysicsWorld();
    world.add_ground("ground", -8.0, 0.0, 8.0, 0.0);
    world.add_box("support", 0.0, 1.5, 0.12, 3.0, 1.5, 80.0, "support");
    world.add_projectile("shot", -3.0, 1.5, 18.0, 0.0, 0.12);
    outcome = world.simulate(max_steps=900);
    assert outcome.contacted("shot", "support"), "thin support was not hit";
    assert outcome.steps == 900, "simulation ignored its step bound";
}

test "a restored core collides after its shape was removed" {
    world = PhysicsWorld();
    world.add_ground("ground", -2.0, 0.0, 30.0, 0.0);
    world.add_static_box("core", 8.0, 1.0, 0.8, 0.8, 0.2);
    saved = world.capture();
    world.hurt("core", 5.0);
    broken = world.find("core");
    assert broken is not None and broken.broken;
    world.add_projectile("shot", 4.0, 1.0, 12.0, 0.0, 0.16);
    missed = world.simulate(max_steps=400);
    assert not missed.contacted("shot", "core");
    world.restore(saved);
    healed = world.find("core");
    assert healed is not None and not healed.broken;
    world.drop_projectiles();
    world.add_projectile("shot", 4.0, 1.0, 12.0, 0.0, 0.16);
    hit = world.simulate(max_steps=400);
    assert hit.contacted("shot", "core");
}

test "broken brace lets a leaning support rotate and fall" {
    world = PhysicsWorld();
    world.add_ground("ground", -8.0, 0.0, 8.0, 0.0);
    world.add_braced_post("post", 0.0, 0.0, 0.14, 3.2, 0.22, 1.0);
    held = world.simulate(max_steps=30);
    held_post = held.body("post");
    assert abs(held_post.angle - 0.22) < 0.08, "brace failed to hold the post";
    assert not held_post.broken;
    world.add_projectile("shot", -2.4, 2.2, 22.0, 0.2, 0.16);
    fallen = world.simulate(max_steps=1800);
    assert fallen.contacted("shot", "post"), "projectile missed the braced post";
    post = fallen.body("post");
    assert post.broken, "contact did not break the brace";
    assert abs(post.angle) > 0.7, "broken support did not rotate";
    assert post.y < held_post.y - 0.35, "broken support did not fall";
}
