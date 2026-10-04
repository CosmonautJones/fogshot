# Runtime

Recorded: 2026-10-04. These commands were run in this workspace. Versions below are the ones those commands printed.

## Toolchain

| Piece | Pin | Evidence |
|---|---|---|
| Jac | 0.37.23 | `jac --version` → `jac 0.37.23 (Linux x86_64)`. Installer: `curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jaseci/main/scripts/install.sh \| bash -s -- --version 0.37.23`. Same version as [jaclang.org](https://jaclang.org/docs/latest) v0.37 docs and the JacBrain `.jac-version` pin. |
| Bundled Python | 3.14.6 | `/workspace/.jac/venv/bin/python3 -c "import sys; print(sys.version)"` → `3.14.6 (main, Jan  1 1970, 00:00:00) [Clang 21.1.0]` |
| Pymunk | 7.3.0 | `jac install "pymunk==7.3.0"`, then `import pymunk; print(pymunk.version)` → `7.3.0`. Solver is third-party Pymunk (Munk2D), not Jac. |
| Phaser | 3.90.0 | `jac install` / bun printed `phaser@3.90.0`. Phaser 4.2.1 is the newer major and is not the pin. The package is installed under `.jac/client`. No browser scene has been executed yet. |
| React | 19.3.0 | bun install output from `jac install` |

`jac.toml` pins those versions. Jac 0.37 removed `cl` / `sv` / `na` source markers. Placement is inferred, with `[placement] default = "server"` and `[placement.pins]` for authoritative modules.

## Pymunk import seam

A direct Jac import does not typecheck against this Pymunk release:

```text
import pymunk;
```

`jac run` of that import stopped in Pymunk's own `body.py` with:

```text
error[E1030]: Type "float" has no attribute "setter"
```

The source that triggers it is `@angle.setter` on `Body.angle`, which is annotated `-> float`. Jac 0.37.23 parses imported Python and rejects that setter. Game code therefore loads Pymunk inside a `::py::` function, `_pymunk()`, which the Jac checker does not walk. Collision callbacks, brace removal, and the step loop stay in Jac. Pymunk 7 removed `Space.add_collision_handler`; the working call is `Space.on_collision(..., post_solve=...)`.

Returned Pymunk objects are `Unknown` to the checker. Attribute writes need `as any`. Numeric reads that Jac must store in `float` fields go through small `::py::` helpers (`_pose`, `_impulse`, `_world_pair`) because `Unknown` has no attributes (E1032) and `float(Unknown)` is rejected (E1053).

## Commands that passed

```text
JAC_TEST_STRICT=1 jac test tests/physics_driver_tests.jac tests/scene_host_tests.jac -v
```

Result: `3 passed in 1.05s`

- `projectile contacts a thin support`
- `broken brace lets a leaning support rotate and fall`
- `mount dispose remount keeps a single handler set`

`jac check physics/pymunk_driver.jac client/scene_host.jac` exited 0. It still warns `W1037` on explicit `any` at the Pymunk boundary. Those warnings are the seam above, not a silent pass of a typed solver.

`JAC_TEST_STRICT=1` matters. Without it, Jac 0.37 treats a missing local import such as `physics` as an optional dependency and **skips** the file with exit 0. The strict run is the one that failed with `ModuleNotFoundError: No module named 'physics'` before `physics/pymunk_driver.jac` existed.

## Siege shot and allowlist view

```text
JAC_TEST_STRICT=1 jac test tests/siege_view_tests.jac tests/physics_driver_tests.jac -v
```

Result: `7 passed in 0.84s`.

The red run, after renaming the Jac keyword `own`, was `ModuleNotFoundError: No module named 'physics.siege'`.

Measured range for angle `0.15`, power `14`, start `(6, 4)`, radius `0.16`, gravity `(0, -9.81)`, damping `0.85`:

| Quantity | Value |
|---|---|
| Fixed step | `1/180` s |
| Shell and flare budget | 1400 steps, 7.78 simulated seconds |
| Bodies | 1 static ground segment, 1 braced post, 1 projectile |
| Post | base x=20 (midline), width 0.14 m, height 3.2 m, lean 0.22 rad, health 4 |
| First shell impulse | about 4.4, enough to break health 4 once |
| Far post | x=24 is past this shot's landing and was not used |
| Wall time | the seven-test command above finished in 0.84 s |

A flare uses the same contact path with `deal_damage = False`, so the pin stays. `capture` / `restore` rewrites pose, health, and the pin, and removes tracks that were not in the snapshot.

`server/views.jac` builds the serialized view from an allowlist. Enemy health is sent as `-1`. Oversized revealed geometry is clipped to the reveal square. The sentinel fixture `12345.67, -9876.54` is absent from `json.dumps(view.__dict__)`. Visible rows are Python `dict` subclasses so that dump contains the same fields the caller reads as attributes. This is not yet an HTTP response capture.

## Match journal

```text
JAC_TEST_STRICT=1 jac test tests/authority_tests.jac -v
```

Result: `6 passed in 1.13s`.

Red run before `server/authority.jac` existed: `ModuleNotFoundError: No module named 'server.authority'`.

The journal is files under a per-test temp directory (`journal.jsonl`, `seats.json`, `pending.json`). It is not the Jac graph, so unrevealed coordinates are not attached to `root`. `runtime-data/` stays gitignored. No HTTP status code was captured for this slice.

## Supply walk

```text
JAC_TEST_STRICT=1 jac test tests/supply_tests.jac -v
```

Result: `6 passed in 0.80s`. Red run: `ModuleNotFoundError: No module named 'graph'`.

The walk uses `Site` nodes and `Cable` edges. It does not attach them to `root`. Breaking B's braced post sets that mast's `intact` flag false.

## Browser boot

```text
jac check main.jac client/battlefield.jac
jac build
jac run
```

`jac check` exited 0 with warnings: `W1101` because `./mount_field.js` has no Jac stub, `W1102` because Phaser's named exports are untyped, and `W2001` on JSX tag names. `jac build` exited 0. It compiled 9/9 server modules and built the client bundle. `jac run` printed `Server ready`, app `http://localhost:8000/`, API `http://localhost:8001/`.

Phaser 3.90.0's ESM build exports `Game` and `AUTO` by name, so the Jac import does not need a re-export shim. Scene callbacks still live in `client/mount_field.js` because a Jac lambda does not bind Phaser's `this`.

The browser pull is no longer a local fog-edge guide. `server/live.jac` runs the canvas pointer through `release_pull` and Pymunk. `client/mount_field.js` draws `path` from that response. Pointer `(20, 300)` on the 800 by 400 canvas crosses x=20. The siege shot (angle 0.15, power 14, post at x=20, health 4) is a separate fixture and still passes.

Two Playwright contexts joined invite `fogshot`. The second context's response bodies did not contain `12345.67`, `-9876.54`, or `87654.32`. Details and the `32 passed` command are in [BUILD-STATUS.md](BUILD-STATUS.md).

## Not claimed

- JacHammer has not been deployed. This environment has no JacHammer credentials or remote application target.
- The browser shell is the canvas shot (about angle 0, power 5, post at x=21, health 0.5). It is not the siege fixture's 0.15 / power-14 shot.
- Restarting `jac run` replays committed journal shots into a new physics world. The journal stores the shot payload, not a pose snapshot. An uncommitted pending file is dropped.
- An unauthenticated `POST /function/join_seat` with no `Authorization` header returned HTTP 401. The request, status, and body are in [BUILD-STATUS.md](BUILD-STATUS.md).
- Scene-host coverage is the handler set in Jac. The browser path destroys `Phaser.Game` in the effect cleanup.
