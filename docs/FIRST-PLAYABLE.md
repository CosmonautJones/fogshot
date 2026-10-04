# First playable implementation plan

Date: 2026-10-04
Status: Not implemented. All product tasks below remain open.

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

- [ ] Inspect the installed Jac version and version-matched guide; pin compatible released Jac, Phaser, and Pymunk versions.
- [ ] Establish tests for scene mount/dispose/remount without duplicate handlers and for a real server-side collision and rotating support collapse.
- [ ] Prove those tests fail for the intended missing behavior, then implement direct Jac imports and callbacks.
- [ ] Run the actual supported check/test/build commands; record them in docs/RUNTIME.md.
- [ ] Commit and push the verified runtime slice. A native dependency failure is a blocker to report, not permission to replace the design with a mock.

## Task 2: Input and pure rules

- [ ] Define typed shot command (ID, expected revision/turn, weapon, angle, power), private checkpoint, private physics result, public player view, and public replay separately.
- [ ] Test drag cancel, duplicate pointer events, resize/device-pixel ratio, mirrored aim, finite input validation, wrong phase/turn/actor, and victory/draw.
- [ ] Implement pure Jac input conversion and explicit rules. Start with fixed gravity, no wind/spread, and a limited initial guide with no hidden collision query.
- [ ] Verify, commit, and push.

## Task 3: Actual physics

- [ ] Test projectile contact against thin supports, support break causing a fall, contact damage applied once, bounded debris settling, and checkpoint restore.
- [ ] Implement one trusted fixed-step physics driver. Jac owns the damage/break policy. Queue world mutations at solver-safe points.
- [ ] Establish measured limits on bodies, simulation steps, payload size, and latency. Separate simulated seconds from wall time.
- [ ] Store resolved outcomes rather than claim cross-device deterministic replay.
- [ ] Verify, commit, and push.

## Task 4: Private views before online access

- [ ] Write a sentinel-body test that rejects unrevealed coordinates in initial view, replay, errors, polling, and reconnect.
- [ ] Test local reveal boundaries, expired observations, off-patch secondary effects, and oversized geometry clipping.
- [ ] Implement a sole allowlist projection. Exclude private seeds/template selections, health, link topology, and solver internals.
- [ ] Inspect response bytes and built assets, not merely fog on screen.
- [ ] Verify, commit, and push.

## Task 5: Match authority and recovery

- [ ] Bind a session to one of two seats; invitation codes are not shot authority. A third player cannot replace an occupant.
- [ ] Test duplicate command IDs, changed payload with reused ID, stale revision, simultaneous submission, finished match, and unauthenticated access.
- [ ] Implement one verified per-match authority boundary. Do not claim a process lock supports multiple workers.
- [ ] Persist accepted-command journal and pre-shot checkpoint; commit one outcome and next turn consistently.
- [ ] Test restart before and after outcome commit. Retrying must not create another shot or advance an extra turn.
- [ ] Verify, commit, and push.

## Task 6: Playable client

- [ ] Use two browser contexts with separate sessions. Exercise joining, both flares, shell launch, local collapse, fog return, next turn, win/draw, and refresh.
- [ ] Implement Jac scene orchestration and Phaser presentation, original industrial shapes, captions, and reduced shake.
- [ ] Animate only the authoritative permitted result. The client never decides a hidden hit.
- [ ] Capture actual two-client evidence, run the tests/build, commit, and push.

## Task 7: Supply graph

- [ ] Test intact chain, broken only route, alternate path, cyclic graph, separated endpoints, and ownership isolation.
- [ ] Use real Jac nodes/edges/traversal to update the powered indicator after physical breaks. Rubble does not conduct.
- [ ] A disconnected objective remains a target, and the basic shot remains available.
- [ ] Verify, commit, and push.

## Task 8: Hosting and measured report

- [ ] Verify the actual JacHammer version, native dependencies, persistence, process topology, and permitted resources.
- [ ] Run the same two-session/privacy/restart checks remotely before calling the app deployed.
- [ ] Record the real URL only after success; otherwise document the runnable local result and exact deployment blocker.
- [ ] Playtest an intentional miss-correct-hit-collapse sequence; do not infer fun from a passing test suite.
- [ ] Document authored Jac modules, justified adapters, measurements, limitations, source SHA, and the next bounded task.
- [ ] Commit and push the evidence. Stop at the milestone rather than silently expanding scope.

## Completion evidence

Real Jac source; verified check/test/build; physical collapse and thin-support tests; hidden-data tests; idempotency and concurrency; restart recovery; two-session recording; actual graph traversal; measured performance; and truthful local versus deployed status.
