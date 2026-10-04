# Build status

Recorded: 2026-10-04

## Repository

Public repository: https://github.com/CosmonautJones/fogshot

Visibility: public. Default branch: `main`. Bootstrap commit `3d445ed3e2c8e61e22ddfa8891b5cae44773bce1` is on `origin/main` (`git ls-remote` at task start matched that SHA as HEAD). The bootstrap note that said the GitHub repository had not been created is stale.

Gameplay work is on branch `cursor/first-playable-66d6`. This file is updated when a slice is verified. A local commit is not remote progress until its push succeeds.

The authoritative browser match is commit `4d3f4867a7a9d8fe00aa20ade906315e3a919303` on that branch. Push status is recorded at the end of this file after `git push`.

## What runs

Jac 0.37.23, Pymunk 7.3.0, pull-back aim, turn rules, one trusted siege shot, an allowlist view, a two-seat journal, a supply walk, and a Phaser field driven by one shared match.

Combined suite after the authoritative browser shot:

```text
JAC_TEST_STRICT=1 jac test tests/physics_driver_tests.jac tests/scene_host_tests.jac tests/aim_rules_tests.jac tests/siege_view_tests.jac tests/authority_tests.jac tests/supply_tests.jac tests/live_match_tests.jac -v
```

Result after the browser proof: `32 passed in 0.92s`. The same command before the client wiring was `32 passed in 1.88s`. The earlier page-boot suite was `31 passed in 1.02s` without `tests/live_match_tests.jac`.

```text
JAC_TEST_STRICT=1 jac test tests/physics_driver_tests.jac tests/scene_host_tests.jac tests/aim_rules_tests.jac tests/siege_view_tests.jac -v
```

Physics and scene host: `3 passed in 1.05s` on commit `17dea2255c04568aa1525d3dd1d2e50577ef1415` (pushed to `origin/cursor/first-playable-66d6`).

Aim and rules, re-run after the combat-turn fix: `11 passed in 1.11s` on commit `dc98d6baac593541f139f17e9a82947986fd74a5` (pushed). That covers cancel, duplicate pointer, resize, device-pixel ratio, mirrored seat B, non-finite input, a short friendly-side guide, wrong actor/turn/revision, recon-only flares, combat rejecting a flare, a finished match, a win, and a draw.

Match journal, after the siege slice:

```text
JAC_TEST_STRICT=1 jac test tests/authority_tests.jac -v
```

Result: `6 passed in 1.13s`. The red run was `ModuleNotFoundError: No module named 'server.authority'`.

- Two player ids claim seats A and B. A third id is `full`. The same id keeps its seat.
- An empty player id cannot submit, even with the invite. That invite check is in-process. It is not an HTTP 401 yet.
- The same command id and payload returns the stored turn and does not increment `shots`. A changed payload on that id is `conflict`.
- `in_flight` rejects a second submit with `busy`. This is one process flag, not a lock across workers.
- A stale revision is rejected. After both flares, `force_finished` makes the next shell `finished`.
- `pending.json` is the pre-shot checkpoint. `fail_before_commit` leaves that file and does not append a journal line. `reload_table` deletes the pending file and stays at turn 0. A later commit reloads at turn 1, and a retry of that command id stays at one shot.
- `look` and `journal.jsonl` omit sentinel coordinates `12345.67` and `-9876.54`.

Siege shot and private view:

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

Details, the Pymunk `::py::` import seam, and the commands are in [RUNTIME.md](RUNTIME.md). The agent note for later Jac sessions is [JAC-0.37-EVIDENCE.md](JAC-0.37-EVIDENCE.md). A push of that note to `CosmonautJones/jacbrain` was denied to `cursor[bot]` (HTTP 403).

## Limitations

- `jac run` serves `http://localhost:8000/`. A browser pull submits to the one in-process match and the gold dot follows that Pymunk path, including past the fog edge. A hitting shell collapses the braced post during a temporary reveal, then the reveal closes. A second browser joins the same match.
- The shared match is one process-wide object plus `runtime-data/browser-match`. Restarting `jac run` builds a fresh physics world. The journal still stores turn, revision, and shot count, not Pymunk poses, so a restart does not restore a fallen post.
- The scene-host test still counts handler names. The browser mount registers `pointerdown`, `pointermove`, and `pointerup` once and destroys the Phaser game on effect cleanup.
- Direct `import pymunk` does not compile on Jac 0.37.23 (E1030 on `Body.angle.setter`). The solver is still Pymunk, loaded through `_pymunk()`.
- The measured 0.15 / power-14 shell from launcher A lands at the midline. A post at x=24 is past that landing, so the siege fixture places the target at x=20. The browser pull is a different shot: pointer `(20, 300)` on an 800 by 400 canvas is about angle 0 at power 5, against a post at x=21 with health 0.5.
- The in-process view test serializes the projection object. The two-browser proof inspected the second context's HTTP response bodies (64 responses, sentinel absent). That is not a replay, error-page, or reconnect capture, and an unauthenticated HTTP 401 was not recorded.
- Supply reachability is tested on nodes that are not attached to `root`. It is not yet wired to a physical break or a powered indicator on the page.
- JacHammer deployment has not been attempted. This environment has no JacHammer target or credentials.
- `jac check` on the driver warns `W1037` for explicit `any` at the solver boundary.
- Outcomes are the in-memory `SimOutcome` from one process. That is not a cross-device deterministic replay.

## Supply

```text
JAC_TEST_STRICT=1 jac test tests/supply_tests.jac -v
```

Result: `6 passed in 0.80s`. The red run was `ModuleNotFoundError: No module named 'graph'`.

`PowerWalk` follows intact `Cable` edges. A broken relay blocks the only route. An intact alternate still powers the objective. A two-node cycle returns. A separated objective stays a target, and `shot_ready` stays true. Another owner's nodes are neither powered nor targets. `sentinel-supply` is not in `[root -->[?:Site]]`.

## Authoritative browser match

Red run before `server/live.jac` existed:

```text
JAC_TEST_STRICT=1 jac test tests/live_match_tests.jac -v
```

Result: `ModuleNotFoundError: No module named 'server.live'`.

Green run, then the combined suite:

```text
JAC_TEST_STRICT=1 jac test tests/live_match_tests.jac -v
```

Result: `1 passed in 2.28s`.

```text
JAC_TEST_STRICT=1 jac test tests/physics_driver_tests.jac tests/scene_host_tests.jac tests/aim_rules_tests.jac tests/siege_view_tests.jac tests/authority_tests.jac tests/supply_tests.jac tests/live_match_tests.jac -v
```

Result before the client wiring: `32 passed in 1.88s`. Re-run after the browser proof: `32 passed in 0.92s`.

`take_shot` turns a canvas pointer into `release_pull`, submits that angle and power to the journal, then runs Pymunk. Pointer `(20, 300)` on an 800 by 400 canvas is the browser shell. The returned path includes a point with x greater than 20. The braced post at x=21, health 0.5, breaks once and its angle passes 0.7. The shooter's reveal includes `enemy-post` until `now_ms` passes `reveal_until`. After that, seat A's watch text does not contain `enemy-post`. Seat B's watch contains their own post and does not contain `12345.67`, `-9876.54`, or the far marker `87654.32`. The sentinel owner is `hidden`, so neither seat serializes it.

`def:protect join_seat`, `watch_match`, and `loose_shot` share that match for invite `fogshot`. Two browser contexts signed up, logged in, and joined. Seat A then seat B.

Browser proof against `jac run` at `http://localhost:8000/` (API `http://localhost:8001/`), after a clean `runtime-data/browser-match`:

- Context A dataset seat `A`. Context B dataset seat `B`.
- A's flare pull released at about `(20, 300)`. `data-authoritative` became `pymunk`. `data-shot-max-x` was `20.85`. `data-broken` stayed `false`. `data-post-angle` was `0.220`. `data-reveal` opened.
- B's pull released at about `(60, 300)`. A's `data-phase` became `combat`.
- A's shell pull used the same pointer. `data-reveal` was `open`, `data-broken` was `true`, `data-post-angle` was `1.309`, `data-shot-max-x` was `20.85`, and `data-shot-screen-x` was `413` (past the fog edge at 400). The open screenshot shows the tilted post in the dark half and the gold dot at the impact.
- After the reveal window, A's `data-reveal` was `closed`. The closed screenshot no longer draws that post. `data-post-angle` stayed `1.309`.
- B's dataset was seat `B`, phase `combat`, broken `true`, post angle `1.309` (B owns the post).
- All 64 HTTP response bodies captured for context B were scanned. None contained `12345.67`, `-9876.54`, or `87654.32`. At least one contained `enemy-post`, which is B's own structure.
- Page errors on both contexts: none.

Screenshots: `/opt/cursor/artifacts/fogshot-reveal-open.png` and `/opt/cursor/artifacts/fogshot-reveal-closed.png`.

## Remote

`git push -u origin cursor/first-playable-66d6` updated `origin/cursor/first-playable-66d6` from `c82a33d` to `42c418d`. Both of these commits are on that remote branch:

- `4d3f4867a7a9d8fe00aa20ade906315e3a919303` drives the Phaser shot from the shared Pymunk match.
- `42c418de2941759e6aa6d854f95f74fb4d0b028b` records that SHA in this file.

## Next task

Capture an unauthenticated `POST /function/join_seat` and record the HTTP 401. Persist the Pymunk pose in the pre-shot checkpoint so a restart restores the fallen post. Tie a physical break to the supply walk and show that on the page. JacHammer stays unattempted until a real remote target and credentials exist.
