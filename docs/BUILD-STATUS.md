# Build status

Recorded: 2026-10-04

## Repository

Public repository: https://github.com/CosmonautJones/fogshot

Visibility: public. Default branch: `main`. Bootstrap commit `3d445ed3e2c8e61e22ddfa8891b5cae44773bce1` is on `origin/main` (`git ls-remote` at task start matched that SHA as HEAD). The bootstrap note that said the GitHub repository had not been created is stale.

Gameplay work is on branch `cursor/first-playable-66d6`. This file is updated when a slice is verified. A local commit is not remote progress until its push succeeds.

## What runs

Jac 0.37.23, Pymunk 7.3.0, pull-back aim, turn rules, one trusted siege shot, and an allowlist view.

```text
JAC_TEST_STRICT=1 jac test tests/physics_driver_tests.jac tests/scene_host_tests.jac tests/aim_rules_tests.jac tests/siege_view_tests.jac -v
```

Physics and scene host: `3 passed in 1.05s` on commit `17dea2255c04568aa1525d3dd1d2e50577ef1415` (pushed to `origin/cursor/first-playable-66d6`).

Aim and rules, re-run after the combat-turn fix: `11 passed in 1.11s` on commit `dc98d6baac593541f139f17e9a82947986fd74a5` (pushed). That covers cancel, duplicate pointer, resize, device-pixel ratio, mirrored seat B, non-finite input, a short friendly-side guide, wrong actor/turn/revision, recon-only flares, combat rejecting a flare, a finished match, a win, and a draw.

Siege shot and private view, this slice:

```text
JAC_TEST_STRICT=1 jac test tests/siege_view_tests.jac tests/physics_driver_tests.jac -v
```

Result: `7 passed in 0.84s`. The earlier red run failed with `ModuleNotFoundError: No module named 'physics.siege'` after a keyword fix (`own` cannot be a Jac variable name).

- A projectile contacts a thin (0.12 m) support inside a 900-step Pymunk run.
- A leaning post held by a pin stays near its brace angle for 30 steps. After a projectile hit drops its health through zero, Jac removes the pin and the post rotates and falls under Pymunk.
- `SceneHost.mount` is idempotent: dispose then mount leaves three pointer handler names, not six.
- A shell at angle 0.15 and power 14 from (6, 4) contacts the midline braced post, breaks it once (`applications == 1`), and leaves it rotated past 0.7 rad after exactly 1400 steps (7.78 simulated seconds at `dt = 1/180`).
- The same contact as a flare records the pair and does not remove the pin. The post stays within 0.08 rad of its braced angle.
- `capture` / `restore` puts the post pose and unbroken flag back and drops the projectile that was added after the checkpoint.
- Seat A's serialized view omits sentinel coordinates `12345.67` and `-9876.54`. An open reveal includes the nearby enemy body and a clipped wide beam, hides enemy health as `-1`, and drops the patch after expiry so `24.0` is absent from `json.dumps(view.__dict__)`.

Details, the Pymunk `::py::` import seam, and the commands are in [RUNTIME.md](RUNTIME.md).

## Limitations

- No playable page. There is no `main.jac` yet, so `jac run` cannot serve Fogshot.
- Phaser 3.90.0 is installed and pinned. Nothing has opened it in a browser.
- The scene test counts handler names. It does not create or destroy a Phaser game.
- Direct `import pymunk` does not compile on Jac 0.37.23 (E1030 on `Body.angle.setter`). The solver is still Pymunk, loaded through `_pymunk()`.
- The measured 0.15 / power-14 shell from launcher A lands at the midline. A post at x=24 is past that landing, so the siege fixture places the target at x=20. This is not a claim that every legal aim reaches the far base.
- The view test serializes the projection object. It does not yet inspect HTTP replay, error, polling, or reconnect bytes.
- No match store, supply graph, or two-client session has been implemented or tested.
- JacHammer deployment has not been attempted.
- `jac check` on the driver warns `W1037` for explicit `any` at the solver boundary.
- Outcomes are the in-memory `SimOutcome` from one process. That is not a cross-device deterministic replay.

## Next task

Bind two authenticated seats to one match, persist an accepted-command journal and pre-shot checkpoint, and reject duplicate command ids, stale revisions, a third occupant, and an invite code used as shot authority. Restart from the journal must not fire the shot twice.
