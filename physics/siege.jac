"""One defended post on the authoritative range. Jac chooses whether the shot damages it."""

import math;
import from physics.pymunk_driver { PhysicsWorld, SimOutcome }

def build_range() -> PhysicsWorld {
    world = PhysicsWorld();
    world.add_ground("ground", -2.0, 0.0, 42.0, 0.0);
    # Angle 0.15 at power 14 from (6, 4) lands on the midline. A post at x=24
    # is past that landing, so this measured target stands at x=20.
    # One post_solve impulse is about 4.4, so health 4 breaks on that single hit.
    world.add_braced_post("enemy-post", 20.0, 0.0, 0.14, 3.2, 0.22, 4.0);
    return world;
}

def _launch(world: PhysicsWorld, shot_id: str, angle: float, power: float, damage: bool) -> SimOutcome {
    world.deal_damage = damage;
    world.add_projectile(
        shot_id,
        6.0,
        4.0,
        power * math.cos(angle),
        power * math.sin(angle),
        0.16
    );
    return world.simulate(max_steps=1400);
}

def fire_shell(world: PhysicsWorld, angle: float, power: float) -> SimOutcome {
    return _launch(world, "shell", angle, power, True);
}

def fire_flare(world: PhysicsWorld, angle: float, power: float) -> SimOutcome {
    return _launch(world, "flare", angle, power, False);
}
