# First playable implementation plan

Date: 2026-10-04
Status: Tasks 1 and 2 are pushed. Task 3 physics behaviors pass locally in `tests/siege_view_tests.jac` and `tests/physics_driver_tests.jac`. No browser match yet.

## Target

Two browsers join a private room. Each side has one launcher and one supported objective. Both use a free, non-damaging opening flare, then alternate free shell attacks. Pull-back aiming is predictable; impact opens a temporary local reveal; supports break and structures fall. A real supply link controls an own-side powered indicator. Destroying all objectives ends the miniature match; simultaneous elimination is a draw.

This slice does not replace the four-objective game concept. It postpones the full economy, combat scouting/breaching loadout, base editor, competitive aim clocks, rankings, monetization, and native engine work.

## Proposed modules

| Module | Authored responsibility |
|---|---|
| main.jac | Version-supported Jac application boot |
| client/battlefield.jac | Phaser lifecycle, input, rendering entitled observations |
| client/hud.jac | Room/phase/status, captions, reduced motion |
| game/contracts.jac | Separate private world and public command/view types |
| game/aim.jac | World-space pull conversion and short guide |
| game/rules.jac | Validation, damage policy, phases, victory |
| physics/pymunk_driver.jac | Trusted solver integration and bounded resolution |
| server/matches.jac | Authenticated membership, serialized writes, recovery |
| server/views.jac | Allowlist-based player projections |
| graph/supply.jac | Nodes, intact segment edges, cycle-safe reachability |
| tests/ | Jac behavior tests and isolated-browser scenarios |

Derive actual codespace annotations and scaffold paths from the selected compiler. Do not expose server modules in the client build.

## Task 1: Runtime integration

- [x] Inspect the installed Jac version and version-matched guide; pin compatible released Jac, Phaser, and Pymunk versions. Jac 0.37.23, Phaser 3.90.0, Pymunk 7.3.0. See docs/RUNTIME.md.
- [x] Establish tests for scene mount/dispose/remount without duplicate handlers and for a real server-side collision and rotating support collapse. `tests/scene_host_tests.jac`, `tests/physics_driver_tests.jac`.
- [x] Prove those tests fail for the intended missing behavior, then implement. Missing modules failed under `JAC_TEST_STRICT=1` with `ModuleNotFoundError`. Direct `import pymunk` does not compile (E1030 on `Body.angle.setter`); the driver loads Pymunk through a `::py::` seam and keeps break policy in Jac. `Space.on_collision` is the Pymunk 7 callback. Phaser itself is not mounted yet.
- [x] Run the actual check and test commands; record them in docs/RUNTIME.md. `jac build` has not been run. There is no servable `main.jac` yet.
- [x] Commit and push the verified runtime slice. `17dea2255c04568aa1525d3dd1d2e50577ef1415` on `origin/cursor/first-playable-66d6`.

## Task 2: Input and pure rules

- [x] Test drag cancel, duplicate pointer events, resize/device-pixel ratio, mirrored aim, finite input validation, wrong phase/turn/actor, and victory/draw. `tests/aim_rules_tests.jac`, 11 passed.
- [x] Implement pure Jac input conversion and explicit rules. Fixed gravity, no wind or spread, and a short guide that stops at the midline without a collision query. `game/aim.jac`, `game/rules.jac`.
- [ ] Typed private checkpoint, private physics result, public player view, and public replay are still task 4. Shot command fields are the `accept_shot` parameters (actor, revision, turn, weapon, angle, power). A command id belongs with match authority.
- [x] Commit and push this slice. `dc98d6baac593541f139f17e9a82947986fd74a5` on `origin/cursor/first-playable-66d6`.

## Task 3: Actual physics

- [x] Test projectile contact against thin supports, support break causing a fall, contact damage applied once, bounded debris settling, and checkpoint restore. `tests/physics_driver_tests.jac` and `tests/siege_view_tests.jac`. The step budget is the settle bound: shell and flare runs assert `steps == 1400`.
- [x] Implement one trusted fixed-step physics driver. Jac owns the damage/break policy. Queue world mutations at solver-safe points. `physics/pymunk_driver.jac`, `physics/siege.jac`. Damage is applied once per contact pair per `simulate` call, and the pin is removed after the step.
- [x] Establish measured limits on bodies, simulation steps, payload size, and latency. Separate simulated seconds from wall time. Recorded in [RUNTIME.md](RUNTIME.md): `dt = 1/180`, 1400 steps = 7.78 simulated seconds, three tracked bodies in the siege fixture. Payload size and browser latency are still unmeasured because there is no served match.
- [x] Store resolved outcomes rather than claim cross-device deterministic replay. Callers keep the returned `SimOutcome`. Nothing claims the same bytes on another machine.
- [x] Verify, commit, and push. `f5d9486466eecd6530ae05a582b2cc998d4dcc81` on `origin/cursor/first-playable-66d6`.

## Task 4: Private views before online access

- [ ] Write a sentinel-body test that rejects unrevealed coordinates in initial view, replay, errors, polling, and reconnect.
- [ ] Test local reveal boundaries, expired observations, off-patch secondary effects, and oversized geometry clipping.
- [ ] Implement a sole allowlist projection. Exclude private seeds/template selections, health, link topology, and solver internals.
- [ ] Inspect response bytes and built assets, not merely fog on screen.
- [ ] Verify, commit, and push.

## Task 5: Match authority and recovery

- [x] Bind a session to one of two seats; invitation codes are not shot authority. A third player cannot replace an occupant. `tests/authority_tests.jac`. Seats are player ids in this process. JWT `def:protect` binding is still open.
- [x] Test duplicate command IDs, changed payload with reused ID, stale revision, simultaneous submission, finished match, and unauthenticated access. Simultaneous means the in-process `in_flight` flag. Unauthenticated means an empty player id, not a captured HTTP 401.
- [x] Implement one verified per-match authority boundary. Do not claim a process lock supports multiple workers. `server/authority.jac`.
- [x] Persist accepted-command journal and pre-shot checkpoint; commit one outcome and next turn consistently. `journal.jsonl` is the commit. `pending.json` is the checkpoint and is deleted on reload when no commit line exists. The checkpoint stores turn, revision, and shot count, not Pymunk poses.
- [x] Test restart before and after outcome commit. Retrying must not create another shot or advance an extra turn.
- [x] Verify, commit, and push. `d223c1c9ceb19997c88d44c5354ffd55a2c76688` on `origin/cursor/first-playable-66d6`. HTTP 401 remains open, as the unauthenticated case in that commit is an empty player id.

## Task 6: Playable client

- [x] Two browser contexts with separate sessions joined one match. Both flares and the shell were pulled on the page. The shell collapsed the braced post, the reveal opened, then the reveal closed. Win/draw and refresh-after-restart are still open. `tests/live_match_tests.jac` and the browser capture in [BUILD-STATUS.md](BUILD-STATUS.md).
- [x] Jac scene orchestration and Phaser presentation. The caption reports seat, phase, and weapon. Shapes are original rectangles and a circle. Reduced shake was not added.
- [x] The drawn projectile is the server path. `client/mount_field.js` does not clamp that path to the fog edge and does not decide the hit.
- [x] Two-client evidence is in [BUILD-STATUS.md](BUILD-STATUS.md). The second context's response bodies omit `12345.67`, `-9876.54`, and `87654.32`.

`jac run` serves `main.jac` at `http://localhost:8000/`. Phaser 3.90.0 logs `Phaser v3.90.0 (WebGL | Web Audio)`. A pull submits `loose_shot`. The gold dot follows the returned path past the fog edge. A hitting shell draws the fallen post only while that seat's reveal is open.

## Task 7: Supply graph

- [x] Test intact chain, broken only route, alternate path, cyclic graph, separated endpoints, and ownership isolation. `tests/supply_tests.jac`.
- [x] Use real Jac nodes/edges/traversal to update the powered indicator after physical breaks. Rubble does not conduct. `graph/supply.jac` uses `Site`, `Cable`, and `PowerWalk`. The walk is not yet triggered by a Pymunk break, so the page has no powered lamp.
- [x] A disconnected objective remains a target, and the basic shot remains available. `shot_ready` is true in each of those cases.
- [x] Verify, commit, and push. `ad5f899750a8cc41d5595c776dfdedd0457a9150` on `origin/cursor/first-playable-66d6`.

## Task 8: Hosting and measured report

- [ ] Verify the actual JacHammer version, native dependencies, persistence, process topology, and permitted resources.
- [ ] Run the same two-session/privacy/restart checks remotely before calling the app deployed.
- [ ] Record the real URL only after success; otherwise document the runnable local result and exact deployment blocker.
- [ ] Playtest an intentional miss-correct-hit-collapse sequence; do not infer fun from a passing test suite.
- [ ] Document authored Jac modules, justified adapters, measurements, limitations, source SHA, and the next bounded task.
- [ ] Commit and push the evidence. Stop at the milestone rather than silently expanding scope.

## Completion evidence

Real Jac source; verified check/test/build; physical collapse and thin-support tests; hidden-data tests; idempotency and concurrency; restart recovery; two-session recording; actual graph traversal; measured performance; and truthful local versus deployed status.
