# Build status

Recorded: 2026-10-04

## Repository

Public repository: https://github.com/CosmonautJones/fogshot

Visibility: public. Default branch: `main`. Bootstrap commit `3d445ed3e2c8e61e22ddfa8891b5cae44773bce1` is on `origin/main` (`git ls-remote` at task start matched that SHA as HEAD). The bootstrap note that said the GitHub repository had not been created is stale.

Gameplay work is on branch `cursor/first-playable-66d6`. This file is updated when a slice is verified. A local commit is not remote progress until its push succeeds.

## What runs

Jac 0.37.23, Pymunk 7.3.0, and the Jac handler lifecycle in `client/scene_host.jac`.

`JAC_TEST_STRICT=1 jac test tests/physics_driver_tests.jac tests/scene_host_tests.jac -v` → `3 passed in 1.05s`.

- A projectile contacts a thin (0.12 m) support inside a 900-step Pymunk run.
- A leaning post held by a pin stays near its brace angle for 30 steps. After a projectile hit drops its health through zero, Jac removes the pin and the post rotates and falls under Pymunk.
- `SceneHost.mount` is idempotent: dispose then mount leaves three pointer handler names, not six.

Details, the Pymunk `::py::` import seam, and the commands are in [RUNTIME.md](RUNTIME.md).

## Limitations

- No playable page. There is no `main.jac` yet, so `jac run` cannot serve Fogshot.
- Phaser 3.90.0 is installed and pinned. Nothing has opened it in a browser.
- The scene test counts handler names. It does not create or destroy a Phaser game.
- Direct `import pymunk` does not compile on Jac 0.37.23 (E1030 on `Body.angle.setter`). The solver is still Pymunk, loaded through `_pymunk()`.
- No match, fog, reveal, privacy projection, supply graph, or two-client session has been implemented or tested.
- JacHammer deployment has not been attempted.
- `jac check` on the driver warns `W1037` for explicit `any` at the solver boundary.

## Next task

Pure aim conversion and shot-command validation: drag cancel, duplicate pointer events, resize and device-pixel ratio, mirrored aim, finite inputs, wrong phase/turn/actor, and victory/draw. Write the failing behavior tests first.
