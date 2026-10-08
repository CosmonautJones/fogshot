"""Supply power follows intact Jac edges. A dark objective is still a target."""

import from graph.supply { Cable, Site, assess }

test "an intact chain powers the objective" {
    source = Site(name="gen-a", owner="A", kind="source", intact=True);
    relay = Site(name="relay-a", owner="A", kind="link", intact=True);
    core = Site(name="core-a", owner="A", kind="objective", intact=True);
    source +>:Cable():+> relay;
    relay +>:Cable():+> core;
    status = assess(source, [core]);
    assert "core-a" in status.powered;
    assert "core-a" in status.targets;
    assert status.shot_ready;
}

test "a broken relay cuts the only route and the core stays a target" {
    source = Site(name="gen-cut", owner="A", kind="source", intact=True);
    relay = Site(name="relay-cut", owner="A", kind="link", intact=False);
    core = Site(name="core-cut", owner="A", kind="objective", intact=True);
    source +>:Cable():+> relay;
    relay +>:Cable():+> core;
    status = assess(source, [core]);
    assert "core-cut" not in status.powered;
    assert "core-cut" in status.targets;
    assert status.shot_ready;
}

test "an alternate intact path still powers the objective" {
    source = Site(name="gen-alt", owner="A", kind="source", intact=True);
    blocked = Site(name="relay-blocked", owner="A", kind="link", intact=False);
    open_relay = Site(name="relay-open", owner="A", kind="link", intact=True);
    core = Site(name="core-alt", owner="A", kind="objective", intact=True);
    source +>:Cable():+> blocked;
    blocked +>:Cable():+> core;
    source +>:Cable():+> open_relay;
    open_relay +>:Cable():+> core;
    status = assess(source, [core]);
    assert "core-alt" in status.powered;
}

test "a cycle does not trap the walk" {
    source = Site(name="gen-loop", owner="A", kind="source", intact=True);
    left = Site(name="loop-left", owner="A", kind="link", intact=True);
    right = Site(name="loop-right", owner="A", kind="link", intact=True);
    core = Site(name="core-loop", owner="A", kind="objective", intact=True);
    source +>:Cable():+> left;
    left +>:Cable():+> right;
    right +>:Cable():+> left;
    right +>:Cable():+> core;
    status = assess(source, [core]);
    assert "core-loop" in status.powered;
}

test "a separated objective is a target without power" {
    source = Site(name="gen-far", owner="A", kind="source", intact=True);
    core = Site(name="core-far", owner="A", kind="objective", intact=True);
    status = assess(source, [core]);
    assert "core-far" not in status.powered;
    assert "core-far" in status.targets;
    assert status.shot_ready;
}

test "another owner's link is not this seat's power or target" {
    source = Site(name="gen-own", owner="A", kind="source", intact=True);
    foreign = Site(name="relay-b", owner="B", kind="link", intact=True);
    core = Site(name="core-b", owner="B", kind="objective", intact=True);
    source +>:Cable():+> foreign;
    foreign +>:Cable():+> core;
    hidden = Site(name="sentinel-supply", owner="B", kind="objective", intact=True);
    status = assess(source, [core, hidden]);
    assert "core-b" not in status.powered;
    assert "core-b" not in status.targets;
    assert "sentinel-supply" not in status.targets;
    attached = [item.name for item in [root -->[?:Site]]];
    assert "sentinel-supply" not in attached;
}
