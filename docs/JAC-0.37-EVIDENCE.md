# Fogshot evidence for Jac 0.37.23

Durable copy. A push of this note to https://github.com/CosmonautJones/jacbrain
branch `cursor/fogshot-evidence-66d6` failed: `Permission to CosmonautJones/jacbrain.git denied to cursor[bot]` (HTTP 403). The local jacbrain commit was `d3dad9df1456b7ea33d246ca646072d23f6da69b` and is not on the remote.

Scope: Jac 0.37.23 on Linux x86_64, recorded 2026-10-04 from the public game
https://github.com/CosmonautJones/fogshot branch `cursor/first-playable-66d6`.
This note is original evidence for later agents. It is not a copy of the Jac
manual. A compiler pass on a snippet is not a behavior test. The commands
below were run in the Fogshot workspace unless a line says otherwise.

## What was built

Fogshot is a Jac-first siege game. Jac owns rules, turn checks, the supply
walk, and the allowlist view. Pymunk 7.3.0 is the third-party solver. Phaser
3.90.0 is the third-party renderer. Neither one is written in Jac.

Pushed commits on that branch, after bootstrap `3d445ed3e2c8e61e22ddfa8891b5cae44773bce1`:

| SHA | Behavior |
|---|---|
| `17dea2255c04568aa1525d3dd1d2e50577ef1415` | Pymunk projectile hits a 0.12 m support. A broken pin lets a leaning post rotate and fall. |
| `dc98d6baac593541f139f17e9a82947986fd74a5` | Pull-back aim and turn rules. Recon advances only after both flares. |
| `f5d9486466eecd6530ae05a582b2cc998d4dcc81` | One shell breaks the midline post once. A flare does not. Checkpoint restore. Sentinel coordinates stay out of the view dump. |
| `d223c1c9ceb19997c88d44c5354ffd55a2c76688` | Two seats and a file journal. A retry does not fire again. An empty player id cannot shoot. |
| `ad5f899750a8cc41d5595c776dfdedd0457a9150` | `PowerWalk` follows intact `Cable` edges and does not attach those nodes to `root`. |
| `bc8eab295cfd4b31dd357ea81dda0db213017770` | `jac run` serves a Phaser field. A browser pull stops on the fog boundary. |
| `9e2666d5069405a1604a77925ee117486459933e` | Ignore local Playwright artifacts. |

Combined behavior suite after the page boot:

```text
JAC_TEST_STRICT=1 jac test tests/physics_driver_tests.jac tests/scene_host_tests.jac tests/aim_rules_tests.jac tests/siege_view_tests.jac tests/authority_tests.jac tests/supply_tests.jac -v
```

Result: `31 passed in 1.02s`.

`jac build` exited 0 and compiled 9/9 server modules. `jac run` printed
`Server ready`, app `http://localhost:8000/`, API `http://localhost:8001/`.
The browser console logged `Phaser v3.90.0 (WebGL | Web Audio)`. A straight
pull left the projectile on the fog edge and did not draw it in the dark half.
That projectile is local presentation in `client/mount_field.js`. It is not
the Pymunk shot.

## Toolchain facts that failed when guessed

Jac 0.34 syntax does not compile on 0.37.23. There are no `cl` / `sv` / `na`
source markers and no `.cl.jac` / `.sv.jac` suffixes. Placement is inferred.
Overrides go in `jac.toml`:

```toml
[project]
entry-point = "main"
jac-version = "==0.37.23"

[placement]
default = "server"

[placement.pins]
"physics.*" = "server"
"server.*" = "server"
"graph.*" = "server"
```

`entry-point` is the dotted module name `main`, not `main.jac`. The client
entry observed in the 0.37.23 web-app scaffold is `def:pub app -> JsxElement`
whose body is the JSX expression. There is no wrapper `cl {}` block.

`def:pub` in a server-anchored module is an unauthenticated endpoint.
`def:protect` requires a JWT and runs on the caller's root. The Fogshot
journal does not use `def:protect` yet. Its unauthenticated case is an empty
player id, not a captured HTTP 401.

`jac install` of the web app pulled React 19.3.0, react-dom 19.3.0,
react-router-dom 6.30.6, Vite 6.4.3, and Phaser 3.90.0. Phaser 4.2.1 exists
and was not the pin. The bundled Python for this Jac build was 3.14.6.

## Tests skip unless they are strict

Without `JAC_TEST_STRICT=1`, Jac 0.37 treats a missing local top-level package
such as `physics` as an optional dependency and skips the file with exit 0.
The skip message is not printed. The red run that mattered was:

```text
JAC_TEST_STRICT=1 jac test tests/siege_view_tests.jac -v
```

before `physics/siege.jac` existed: `ModuleNotFoundError: No module named 'physics.siege'`.

Do not name test files `test_*.jac`. Use `test "name" { }` blocks. Tests run
in parallel isolated workers. Keywords cannot be variable names. Observed
rejections: `report`, `static`, `own`. The escape is one backtick before the
word (`own`), not a pair. After a dot, no escape is needed (`view.own`).
`sentinel` as a name inside a list literal also failed with `E0006` in one
draft; the binding was renamed.

`JacTestClient` imports from `jaclang.testing.testing`, not
`jaclang.runtimelib.testing`. Fogshot has not used that client yet.

## Pymunk 7 through a Python seam

Direct `import pymunk` does not typecheck. `jac` walks the installed Python
and stops in `pymunk/body.py` on `@angle.setter`:

```text
error[E1030]: Type "float" has no attribute "setter"
```

The working seam is a `::py::` function. The checker does not walk that block.
Returned objects are `Unknown`. Attribute writes need `as any` (`E1032` on
`Unknown.x`, `E1053` on `float(Unknown)`). Numeric reads go through more
`::py::` helpers. `jac check` then warns `W1037` on the explicit `any`. That
warning is the seam, not a typed solver.

Pymunk 7.3.0 removed `Space.add_collision_handler`. The call that ran is
`space.on_collision(3, 2, post_solve=callback, data={"world": self})`.
`post_solve` is where `total_impulse` is valid. Adding or removing a joint
during the callback is deferred, so Fogshot queues the break and removes the
pin after `space.step`.

Collision types used: ground 1, structure 2, projectile 3. The handler is
3 versus 2. A `fog_id` attribute on the shape identifies the body. Damage is
applied once per pair per `simulate()` via a `damaged` list. Gravity is
`(0, -9.81)`, damping `0.85`, `dt = 1/180`.

A braced post is a `PivotJoint` at the base plus a `PinJoint` at the top.
Breaking removes only the pin, so the post rotates about the pivot. The pivot
must sit about 0.35 above the ground segment or the hinge jams and the post
does not fall. Health 4 breaks on the first shell impulse, which measured
about 4.4 for the siege shot. An earlier close-range probe saw impulses
around 16-21; do not reuse that number for the 0.15 / power-14 shot.

Measured siege shot: angle `0.15`, power `14`, start `(6, 4)`, radius `0.16`,
1400 steps (7.78 simulated seconds). It hits a braced post whose base is at
x=20 and topples it (`angle` past 0.7, `applications == 1`). The same contact
with damage disabled records the pair and leaves the lean within 0.08 rad.
A post at x=24 is past this shot's landing. That was measured by stepping
Pymunk, not inferred.

`capture()` / `restore()` rewrite pose, velocity, health, and the pin, and
drop tracks that were not in the snapshot. `simulate` always runs the full
step budget. The projectile does not sleep inside 900 steps, so the thin
support test asserts `steps == 900` plus contact, not an early stop.

## Views, journal, and graph

`json.dumps(view.__dict__)` only works if nested rows are JSON-ready. Fogshot
uses `dict` subclasses for visible rows so attribute reads (`.health`) and
`json.dumps` see the same fields. Enemy health is sent as `-1`. An oversized
body is clipped to the reveal square. The fixture coordinates `12345.67` and
`-9876.54` are absent from the seat dump, from the expired reveal, and from
`journal.jsonl`.

Do not hang unrevealed geometry on `root`. `GET /graph` is a live visualizer.
The supply nodes are walked from the source node and are not connected to
`root`. The test asserts `sentinel-supply` is absent from
`[root -->[?:Site]]`.

`edge Cable: Site --> Site` needs the endpoint clause. A bare `edge` is
`E2086` in 0.37. Connect with `source +>:Cable():+> relay`. Visit with
`visit [->:Cable:intact == True:->]`. A walker `has reports: list[list[str]] = []`
or spawn treats `reports` as a required parameter. One `report` of a list
arrives as `reports[0]`.

The match journal is `journal.jsonl` plus `pending.json`. Reload deletes a
pending file that has no commit line, so a crash before commit does not leave
a shot. A repeated command id returns the stored turn. A changed payload on
that id is `conflict`. `in_flight` is one process flag. It is not a lock
across workers. The checkpoint stores turn, revision, and shot count, not
Pymunk poses.

Both flares move the match to combat and set the active seat back to A only
while `phase == "recon"`. Doing that on later shots stuck the turn on A.
That bug was fixed and covered by `tests/aim_rules_tests.jac` (`11 passed in
1.11s` on `dc98d6b`).

## Phaser

`import from "phaser" { AUTO, Game }` resolves against Phaser 3.90.0's named
ESM exports. `jac check` warns `W1102` and still exits 0. A Jac lambda does
not bind Phaser's scene `this`, so create/update/input callbacks live in
`client/mount_field.js`. The effect cleanup calls `game.destroy(true)`.
`SceneHost` in Jac still only counts handler names. The browser showed three
handler names on the field element (`pointerdown`, `pointermove`,
`pointerup`).

## Browser match

`def:protect join_seat`, `watch_match`, and `loose_shot` share one
`LiveMatch`. A canvas pointer becomes `release_pull`, then Pymunk. The page
draws that path. Pointer `(20, 300)` on 800 by 400 is about angle 0 at power
5. The browser post is at x=21 with health 0.5, separate from the siege post
at x=20 with health 4. The shell's returned path has x greater than 20, the
post angle passes 0.7, and the reveal includes `enemy-post` until expiry.
Seat B's serialized watch omits `12345.67`, `-9876.54`, and `87654.32`.

A two-context browser run confirmed seats A and B, a collapsed post at angle
about 1.309 while the reveal was open, the reveal closing afterward, and 64
response bodies from the second context with those sentinel strings absent.
`enemy-post` was present in that context because B owns it.

## Not proven

- No `def:protect` HTTP 401 was captured.
- The supply walk is not triggered by a Pymunk break.
- A process restart does not restore the fallen post. The journal stores
  turn, revision, and shot count, not Pymunk poses.
- JacHammer was not deployed. No credentials or remote application target
  were available. Do not treat `jac run` on localhost as a deployment.
- Outcomes from one process are not a cross-device deterministic replay.

When jacbrain is writable, ingest this file with `python -m jacbrain ingest docs/JAC-0.37-EVIDENCE.md --project fogshot`.
Do not ingest `.jacbrain` SQLite databases, seat tokens, or `runtime-data/`.
