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

## Not claimed

- No `main.jac` server is running.
- Phaser has not mounted a canvas.
- JacHammer has not been deployed.
- `jac build` has not been run.
- Scene-host coverage is the handler set in Jac. It is not yet a browser dispose of a Phaser.Game.
