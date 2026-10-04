"""Pointer-handler lifecycle for the battlefield scene.

Mount is idempotent. Dispose drops the set. A later mount registers one set
again, so React remounts do not stack Phaser pointer listeners.
"""

obj SceneHost {
    has mounted: bool = False;
    has names: list[str] = [];

    def mount() -> None {
        if self.mounted {
            return;
        }
        self.mounted = True;
        self.names = ["pointerdown", "pointermove", "pointerup"];
    }

    def dispose() -> None {
        self.mounted = False;
        self.names = [];
    }

    def handler_count() -> int {
        return len(self.names);
    }
}
