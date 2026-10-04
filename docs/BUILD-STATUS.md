# Build status

Recorded: 2026-10-04

## Repository

Public repository: https://github.com/CosmonautJones/fogshot

Visibility: public. Default branch: `main`. Bootstrap commit `3d445ed3e2c8e61e22ddfa8891b5cae44773bce1` is on `origin/main` (`git ls-remote` at task start matched that SHA as HEAD). The bootstrap note that said the GitHub repository had not been created is stale.

Gameplay work is on branch `cursor/first-playable-66d6`. This file is updated when a slice is verified. A local commit is not remote progress until its push succeeds.

The authoritative browser match is commit `4d3f4867a7a9d8fe00aa20ade906315e3a919303` on that branch. Push status is recorded at the end of this file after `git push`.

## What runs

Jac 0.37.23, Pymunk 7.3.0, pull-back aim, turn rules, one trusted siege shot, an allowlist view, a two-seat journal, a supply walk tied to the braced post, one core per side, rematch, and a Phaser field driven by one shared match.

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
- Supply reachability is tested on nodes that are not attached to `root`. A broken braced post now cuts B's only cable, and the page shows that as B's own lamp. The lamp is a boolean for the viewing seat. Enemy core coordinates stay out of that seat's payload.
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

## Cores, supply, victory, rematch

Red run after the rules were in the working tree and before the own-core assertion was corrected:

```text
JAC_TEST_STRICT=1 jac test tests/outcome_tests.jac -v
```

Result: `AssertionError` at `assert "4.25" not in opened`. That string is seat A's own core in A's view. The opponent check stays on B's payload.

Green run of the same file: `1 passed in 1.07s`.

Combined suite after the live brace clearance change (`0.22` on the browser post; the siege pivot stays `0.35`):

```text
JAC_TEST_STRICT=1 jac test tests/physics_driver_tests.jac tests/scene_host_tests.jac tests/aim_rules_tests.jac tests/siege_view_tests.jac tests/authority_tests.jac tests/supply_tests.jac tests/live_match_tests.jac tests/outcome_tests.jac -v
```

Result: `33 passed in 1.16s`.

`tests/outcome_tests.jac` fires the canvas pointers. A's shell at `(20, 300)` breaks the post, leaves `result` empty, and does not put `core-b` in A's JSON. B's watch then has `own_powered` false, `shot_ready` true, and `own_core` true. B's shell is accepted. A's lob at `(10, 390)` sets `result` to `A` and `phase` to `finished`. A later shell is `finished`. After `reveal_until`, A's watch omits `core-b`. B's watch omits `4.25`, `12345.67`, `-9876.54`, and `87654.32`. `rematch_room` restores recon, an intact mast, and `own_powered` true.

The browser post uses pivot clearance `0.22` so a flat shell still hits when the pointer is a pixel off the launcher line. At clearance `0.35`, angle `-0.00457` rolls under the brace. The siege fixture is unchanged.

Browser proof against `jac run` at `http://localhost:8000/` (API `http://localhost:8001/`), after wiping `runtime-data/browser-match` and restarting `jac run`. Two Playwright contexts, not two tabs.

- Joined as seat A and seat B. Both started in `recon` with `data-powered=true`, `data-shot-ready=true`, `data-enemy-cores=1`, and `data-own-core=true`.
- Both flares landed. Phase became `combat`.
- A's shell released at about `(20, 308)`. A's `data-broken` became `true`, `data-post-angle` was `1.347`, and `data-shot-max-x` was `20.78`. B's `data-powered` became `false`, `data-shot-ready` stayed `true`, `data-phase` stayed `combat`, and `data-result` stayed empty. B's caption read `supply dark / shell ready`.
- B then fired a shell at about `(60, 300)`. The match stayed in combat with an empty result. B's lamp stayed dark.
- A's lob released at about `(10, 390)`. Both seats showed `data-result=A` and `data-phase=finished`. A's `data-shot-ready` was `false` and `data-enemy-cores` was `0`. B's `data-own-core` was `false`. A's caption included `Result A.`
- A's `data-reveal` returned to `closed`.
- B clicked Rematch. Both seats returned to `recon` with an empty result. B's `data-powered` and `data-own-core` were `true` again, and `data-shot-ready` was `true`.
- All 79 HTTP response bodies captured for context B were scanned. None contained `12345.67`, `-9876.54`, `87654.32`, `core-a`, or `4.25`.
- Page errors on both contexts: none.

Screenshots: `/opt/cursor/artifacts/fogshot-supply-dark.png` (B's dark lamp while the shell is still ready) and `/opt/cursor/artifacts/fogshot-result-a.png` (A's finished match, result A).

The field dataset can keep the last seen `data-broken` and `data-post-angle` after rematch. Phase, the lamp, the core flags, and the server view are what reset. One core per side is this miniature match, not the four-objective economy.

## Remote

`git push -u origin cursor/first-playable-66d6` updated `origin/cursor/first-playable-66d6`. These commits are on that remote branch:

- `4d3f4867a7a9d8fe00aa20ade906315e3a919303` drives the Phaser shot from the shared Pymunk match.
- `42c418de2941759e6aa6d854f95f74fb4d0b028b` records that SHA in this file.
- `4aba47fd4bf3147bb943989ec61cadcdc5564e00` records the pushed match commits.
- `2811e0b6396e77fb6d2a392317d2e0ff6b841eee` lets a broken supply stay playable and a dead core end the match.
- `397252ddc70e4e82ef29123a591f69c864df1301` shows the own-side supply lamp and the rematch control.
- `13c257d3478090cf7fe0941b66828b727549f6f5` seats the live brace lower so a flat shell cannot slip under it.

## Next task

Capture an unauthenticated `POST /function/join_seat` and record the HTTP 401. Persist the Pymunk pose in the pre-shot checkpoint so a restart restores the fallen post. JacHammer stays unattempted until a real remote target and credentials exist.
