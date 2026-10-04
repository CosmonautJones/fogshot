"""Scene handler lifecycle. Remounting must not stack pointer handlers."""

import from client.scene_host { SceneHost }

test "mount dispose remount keeps a single handler set" {
    host = SceneHost();
    assert host.handler_count() == 0;
    host.mount();
    assert host.handler_count() == 3;
    host.mount();
    assert host.handler_count() == 3, "second mount duplicated handlers";
    host.dispose();
    assert host.handler_count() == 0;
    assert not host.mounted;
    host.mount();
    assert host.handler_count() == 3;
    assert host.mounted;
}
