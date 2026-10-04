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
- An empty player id cannot submit, even with the invite. That invite check is in-process. The HTTP 401 for a missing JWT is a separate capture, recorded below.
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
- The shared match is one process-wide object plus `runtime-data/browser-match`. A later boot replays committed journal shots into a fresh physics world, so the fallen post, dark supply, and dead core come back. An uncommitted `pending.json` is still dropped. Replay is this process reading its own journal, not a claim that another machine produces the same bytes.
- The scene-host test still counts handler names. The browser mount registers `pointerdown`, `pointermove`, and `pointerup` once and destroys the Phaser game on effect cleanup.
- Direct `import pymunk` does not compile on Jac 0.37.23 (E1030 on `Body.angle.setter`). The solver is still Pymunk, loaded through `_pymunk()`.
- The measured 0.15 / power-14 shell from launcher A lands at the midline. A post at x=24 is past that landing, so the siege fixture places the target at x=20. The browser pull is a different shot: pointer `(20, 300)` on an 800 by 400 canvas is about angle 0 at power 5, against a post at x=21 with health 0.5.
- The in-process view test serializes the projection object. The two-browser proof inspected the second context's HTTP response bodies (64 responses, sentinel absent). That is not a replay or reconnect capture. The unauthenticated HTTP 401 is recorded below.
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

## QA passes

Independent reads of the projection and of boot, then new Jac tests, then two browser passes.

First `tests/qa_match_tests.jac` run, before the fixes:

```text
JAC_TEST_STRICT=1 jac test tests/qa_match_tests.jac -v
```

Result: `3 failed in 1.84s`.

- Duplicate command id through `take_shot` returned `conflict` because the retry was stamped with the new revision. The shot was not simulated twice, but the retry was not the stored command.
- Restart let `player-c` claim seat A. `boot_match` called `open_table`, which overwrote `seats.json` and ignored `journal.jsonl`, then `_arm` built a standing post.
- The miss assertion also failed at `now_ms` 3000 because seat A's flare reveal was still open. The path itself peaked at x `9.35` and did not hit the post. The test clock was moved to 8000. That was a test bug, not a second physics bug.

After the journal replay, idempotent command id, and corrected miss clock:

```text
JAC_TEST_STRICT=1 jac test tests/qa_match_tests.jac -v
```

Result: `3 passed in 3.19s`.

Full suite:

```text
JAC_TEST_STRICT=1 jac test tests/physics_driver_tests.jac tests/scene_host_tests.jac tests/aim_rules_tests.jac tests/siege_view_tests.jac tests/authority_tests.jac tests/supply_tests.jac tests/live_match_tests.jac tests/outcome_tests.jac tests/qa_match_tests.jac -v
```

Result: `36 passed in 1.38s`.

The QA file covers a wrong-seat shot (`actor`), an empty player (`unauthenticated`, no `core-a` or `4.25`), a shell during recon and a flare during combat (`weapon`), a stale revision (`revision`), a repeated command id (ok, empty path, no second shot), a different aim on that id (`conflict`), a miss at pointer `(100, 390)` with a path and no enemy post in the payload, restart restoring both seats plus the dark supply and the dead core, and rematch restoring both seats before a later boot returns to recon.

Browser pass against `jac run` at `http://localhost:8000/`, two contexts plus a third that arrived after the seats were taken. Phaser layout was not changed.

- The third page caption included `(full)` and its seat stayed empty.
- Seat B pulled during recon. The caption included `(actor)`. Phase stayed `recon`. Seat A then flared successfully.
- After both flares, A's miss released near `(100, 390)`. `data-shot-max-x` was `9.34`, `data-authoritative` was `pymunk`, `data-broken` stayed `false`, and `data-reveal` was `closed`. Supply stayed on.
- A's later shell near `(20, 308)` left B with `data-powered=false`, `data-shot-ready=true`, `data-phase=combat`, and `data-post-angle=1.347`.
- That pass captured 74 HTTP bodies for context B. None contained `12345.67`, `-9876.54`, `87654.32`, `core-a`, or `4.25`. Page errors: none.
- `jac run` was stopped and started again without deleting `runtime-data/browser-match`. The same two emails joined again. B was still seat B, supply dark, shell ready, post angle `1.3466442000713896`. Refreshing A's page kept seat A.
- B fired, A's lob near `(10, 390)` set both pages to result A, and B's `data-own-core` became `false`. Rematch returned both seats to `recon` with supply on and `data-broken=false`.
- The resume pass captured 38 more B bodies. The same five strings were absent. Page errors: none.

Screenshots: `/opt/cursor/artifacts/fogshot-qa-supply-dark.png` and `/opt/cursor/artifacts/fogshot-qa-result-a.png`.

An unseated full page reports supply dark because it has no seat. That caption is the `(full)` code plus an empty seat, not B's lamp. Draw was not played in the browser. The unauthenticated HTTP 401 is recorded below. JacHammer was not deployed.

## Remote

`git push -u origin cursor/first-playable-66d6` updated `origin/cursor/first-playable-66d6`. These commits are on that remote branch:

- `4d3f4867a7a9d8fe00aa20ade906315e3a919303` drives the Phaser shot from the shared Pymunk match.
- `42c418de2941759e6aa6d854f95f74fb4d0b028b` records that SHA in this file.
- `4aba47fd4bf3147bb943989ec61cadcdc5564e00` records the pushed match commits.
- `2811e0b6396e77fb6d2a392317d2e0ff6b841eee` lets a broken supply stay playable and a dead core end the match.
- `397252ddc70e4e82ef29123a591f69c864df1301` shows the own-side supply lamp and the rematch control.
- `13c257d3478090cf7fe0941b66828b727549f6f5` seats the live brace lower so a flat shell cannot slip under it.
- `8d41943be40beb667393356f74a86a22677a5a18` records this core, supply, and rematch evidence.
- `30337d40be0ee84840926cc9de221dfaa60da79f` names that evidence commit.
- `30c236c3eb5bb788bd8130ad5d9c58cf4ccbdc27` restores a restarted match from the journal and ignores a repeated command.
- `b0c8b95ddd7995175af9283dea461aa141281176` lets a refreshed browser reclaim its seat.
- `7be2563b9def5258eb7fd0b61c340b33456722e1` records the QA passes, the journal replay, and the browser restart.
- `52d9f8f6d5a72e741b73dccb70ab33415ad555d5` records the unauthenticated `join_seat` HTTP 401.

## Unauthenticated join

Captured against the already running `jac run` process. API `http://127.0.0.1:8001/`. No `Authorization` header. The status was not invented.

```text
curl -sS -D - -X POST 'http://127.0.0.1:8001/function/join_seat' \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  --data '{"invite":"fogshot"}'
```

Request:

```text
POST /function/join_seat HTTP/1.1
Host: 127.0.0.1:8001
Accept: application/json
Content-Type: application/json

{"invite":"fogshot"}
```

Response at `Date: Sun, 04 Oct 2026 17:02:55 GMT`, request id `0d19c4541d794b06843c51cfd1321d07`:

```text
HTTP/1.1 401 Unauthorized
Server: jac
Content-Type: application/json
Content-Length: 106

{"ok": false, "type": "error", "data": null, "error": {"code": "UNAUTHORIZED", "message": "Unauthorized"}}
```

The same process logged `127.0.0.1 "POST /function/join_seat HTTP/1.1" 401 106 0.7ms 0d19c4541d794b06843c51cfd1321d07`.

`def:protect join_seat` is why this is 401. The live `GET /openapi.json` lists that path with `security: [{"BearerAuth": []}]` and bearer format JWT. This request sent no bearer token. The body is the server error envelope. It is not the function's own `{"ok": false, "code": "unauthenticated", "seat": ""}`, so the function body did not run. The body contains no seat, no core id, and no sentinel coordinate. OpenAPI documents only response 200 for this path. The 401 is from the live call.

The Vite proxy at `http://127.0.0.1:8000/function/join_seat` returned the same status and the same body. Its API request id was `f1f81b14405947b98665e67cf84f6adc`.

## Reveal playback stops

An independent read of `55e51fb` kept the gold dot after the server path was empty. Seat A's `data-shot-screen-x` moved from 324 through the fog edge at 400 and parked at 410.16. Seat B was already at filtered time 4.78 while A's dot was at 0.33s. A's `data-broken` stayed true after the payload cleared it, and the caption still said `shell ready` while `data-your-turn` was false.

Red run, before `stepWatch` cleared an empty list:

```text
node --test tests/playback_client.test.mjs
```

Result: `2 failed` of 7. `an empty watch stops the dot and drops a break the server cleared` kept the previous path. `a filtered tail is not on screen while the shooter is still at the start` drew the sample at time 4.78 when elapsed was 0.33.

The empty watch now drops the path, the collapse, and the dot. A sample is not drawn before its timestamp. `data-broken` follows the payload, including `false`. The caption says `shell waiting` when it is not that seat's turn and `shell ready` when it is. The other seat's path no longer includes the hidden side of the fog. The live match directory is `.fogshot-match`, which the dev inventory skips, so a match write during a client rebuild does not raise `E7005`.

Green:

```text
node --test tests/playback_client.test.mjs
JAC_TEST_STRICT=1 jac test tests/playback_tests.jac -v
```

Node: `7 passed`. Jac playback file: `1 passed in 0.31s`. The full suite, same file list as the 48-test run, was `48 passed in 3.48s`.

Two browsers on `http://127.0.0.1:8000/`, clean `.fogshot-match`. During A's shell, A's shot time moved 0.22, 0.44, 0.67 at screen x 141, 162, 183. B did not show time 4.78. After A's reveal closed, A's `data-reveal` was `closed`, `data-broken` was `false`, `data-post-angle` was `0`, and `data-shot-screen-x` stayed empty on a later read. A's caption was `shell waiting`. B's caption was `supply dark / shell ready`, `data-broken` true, angle `0.9518626481783586`, and the shot dataset empty. No page errors and no Vite overlay. Rectangles and the launcher ring are still placeholders. A's own mast remains visible on A's dark half.

## Next task

Issue comments for #2–#5, then issue #6 Part A: a committed clean-checkout check, a real browser test, and a small GitHub Actions workflow. JacHammer is still not deployed. This environment has no JacHammer credentials or remote application target. One `jac run` process is the supported worker model. Do not treat localhost as a deploy. Basic shots stay free. The four-objective economy is still the later milestone.

## Two outposts

Red run of `tests/outpost_tests.jac`: `1 failed, 1 error in 1.96s`. The shell reveal radius was not `2.6`, and the payload had no `perk`. After the supports existed, the full suite still had 3 failures: the two miss tests expected radius `2.2` while the shooter was connected, and the playback collapse mixed the standing post into the falling post's samples.

A connected shell now scouts at radius 2.6. A disconnected shell stays at 2.2. Flares stay at 3.0 and do not damage. `perk` is `scout` while that seat's supply reaches its core, and empty when it does not. `shot_ready` stays true either way.

B's valley post remains at x=21 and still falls to A's flat shell. A's mast is `post-a` at x=26, on B's approach, so B's flat shell at pointer `(20, 300)` breaks it and A's shell, which stops on the valley post, does not. A static spur at `(18.45, 1.55)` is crushed once by the falling valley post. The shell's pair list does not include that spur. Intact structure contact does not drain health. An extra intact cable keeps B powered after the valley post falls.

Green:

```text
JAC_TEST_STRICT=1 jac test tests/physics_driver_tests.jac tests/scene_host_tests.jac tests/aim_rules_tests.jac tests/siege_view_tests.jac tests/authority_tests.jac tests/supply_tests.jac tests/live_match_tests.jac tests/outcome_tests.jac tests/qa_match_tests.jac tests/clock_authority_tests.jac tests/command_envelope_tests.jac tests/transaction_tests.jac tests/impact_reveal_tests.jac tests/playback_tests.jac tests/outpost_tests.jac -v
```

Result: `48 passed in 4.20s`.

The client bundle also has to emit `client/playback.js`. Importing it from `client/battlefield.jac` is what places it beside `mount_field.js`. Without that, `jac run` returned HTTP 500 for `compiled/client/mount_field.js` (`E7002`, unresolved `./playback.js`).

Two browsers on `http://127.0.0.1:8000/` then joined a clean match. Seat A stayed `supply on / shell ready`. After A's combat shell, seat B read `supply dark / shell ready`, `data-broken=true`, and post angle `0.9518626481783586`. Neither caption contained `12345.67`, `-9876.54`, or `87654.32`. A Vite overlay appeared when the match directory changed during a client rebuild; dismissing it left those captions. This was one local `jac run`, not a deploy.

## Shot playback

Red run of `tests/playback_tests.jac` while `watch` still returned `[]`: `1 failed in 1.32s` at `assert len(watched["path"]) > 3`. The captured path was `[]`. `node --test tests/playback_client.test.mjs` first failed with `ERR_MODULE_NOT_FOUND` for `client/playback.js`.

A shot now stores `[x, y, t]` samples and post `[angle, t]` samples, at most 80 of each. `t` is simulated seconds. Both seats receive the path while the review window is open. Seat A keeps `x <= 20` plus the reveal circle. Seat B keeps `x >= 20` plus that circle. Collapse is sent only when that seat can see the post. An empty seat gets neither. After `reveal_until`, both lists are empty. Restart from `canonical.json` restores them. The client samples by elapsed time, ignores an older epoch or revision, and does not fire on cancel, a second pointer, a release outside the canvas, or `your_turn` false. The server still rejects an illegal shot.

Green:

```text
JAC_TEST_STRICT=1 jac test tests/physics_driver_tests.jac tests/scene_host_tests.jac tests/aim_rules_tests.jac tests/siege_view_tests.jac tests/authority_tests.jac tests/supply_tests.jac tests/live_match_tests.jac tests/outcome_tests.jac tests/qa_match_tests.jac tests/clock_authority_tests.jac tests/command_envelope_tests.jac tests/transaction_tests.jac tests/impact_reveal_tests.jac tests/playback_tests.jac -v
node --test tests/playback_client.test.mjs
```

Jac result: `46 passed in 2.45s`. Node result: `3 passed`.

## First impact

`tests/impact_reveal_tests.jac` failed first because a flare onto empty ground left `view.reveal` null (`1 failed in 1.28s`). A structure hit now centers the patch on the first structure contact, not the body's final pose. A terrain-only miss centers it on the ground contact. Shell radius is 2.2. Flare radius is 3.0 and does not damage. The old miss assertion that required `reveal` to be null was replaced. Full suite after that change: `45 passed in 3.32s`.

## Shot transaction

`tests/transaction_tests.jac` first failed because `fail_storage` was ignored and the core shot still returned ok (`1 failed in 2.86s`). `tests/physics_driver_tests.jac` first failed `a restored core collides after its shape was removed` because `restore` put the health flag back and left the collider out of the space.

The canonical file is `canonical.json`, version 1, solver `pymunk-7.3.0`. It is replaced only after simulation. A storage or simulation failure restores the prior bodies, joints, supply flags, rules, and command list, and clears `in_flight`. Restart loads that file instead of replaying inputs. Rematch deletes it. An unknown version sets `refused` and `take_shot` returns `snapshot`. This is one process, not a multi-worker lock.

## Command envelope

Red run of `tests/command_envelope_tests.jac` before the arguments existed: compile error `E1051` too many positional arguments. After the arguments existed but `take_shot` still substituted the server revision and re-inferred the weapon: `3 failed in 3.34s`. The flare retry was not ok, the old-revision shell was accepted, and a shell intent on the flare id was accepted.

Green:

```text
JAC_TEST_STRICT=1 jac test tests/physics_driver_tests.jac tests/scene_host_tests.jac tests/aim_rules_tests.jac tests/siege_view_tests.jac tests/authority_tests.jac tests/supply_tests.jac tests/live_match_tests.jac tests/outcome_tests.jac tests/qa_match_tests.jac tests/clock_authority_tests.jac tests/command_envelope_tests.jac -v
```

Result: `41 passed in 1.78s`.

The browser sends epoch, turn, revision, weapon, and reuses a pending command id when `loose_shot` throws. A successful response clears that id. Rematch clears it and increments the match epoch stored in `seats.json`. An exact flare retry after combat does not simulate again. A new command with revision 0 on A's later turn returns `revision`. A changed weapon on the same id returns `conflict`. An epoch-1 command after rematch returns `epoch` and does not open a reveal.

## Stabilization baseline

Fetched `origin/cursor/first-playable-66d6` at `36e8a5321d216ac3e153ba7e5fcad92e9290ef70`. No newer commits. The review patch applied as `863429b15da91d010e6c220265c75a502e76716f` and only adds `docs/reviews`.

Baseline before gameplay edits, Jac 0.37.23:

```text
JAC_TEST_STRICT=1 jac test tests/physics_driver_tests.jac tests/scene_host_tests.jac tests/aim_rules_tests.jac tests/siege_view_tests.jac tests/authority_tests.jac tests/supply_tests.jac tests/live_match_tests.jac tests/outcome_tests.jac tests/qa_match_tests.jac -v
```

Result: `36 passed in 1.53s`. That count was measured again. It is not copied from the older note.

Review findings F01–F07 were still present in that source. F04 (shared password and one room) and hosting stay deferred. No two-browser smoke was rerun before the clock edit; the earlier QA browsers were not repeated as if they were a new result.

## Server clock

Red run of `tests/clock_authority_tests.jac` before `server.clock` existed: `ModuleNotFoundError`. After the pin existed but live match still trusted `now_ms`: `2 failed in 0.64s`. `reveal_until` was not 13000. An open core reveal still published `broken` for the out-of-patch post.

Green, after the server clock and the patch check:

```text
JAC_TEST_STRICT=1 jac test tests/clock_authority_tests.jac tests/live_match_tests.jac tests/outcome_tests.jac tests/qa_match_tests.jac tests/physics_driver_tests.jac tests/scene_host_tests.jac tests/aim_rules_tests.jac tests/siege_view_tests.jac tests/authority_tests.jac tests/supply_tests.jac -v
```

Result: `38 passed in 6.16s`.

HTTP, after a fresh `jac run` on `http://127.0.0.1:8001`, two new users, invite `fogshot`. `POST /function/loose_shot` sent `now_ms` `9000000000000`. `reveal_until` was `1791134749644`, about 3014 ms after the wall clock, not the client stamp. Immediate `POST /function/watch_match` with `now_ms` 0, 1000, and `9000000000000` all kept that same deadline and an open reveal. After 3.3 seconds the same three client times all returned `reveal_until` 0, reveal closed, and no `enemy-post`. Retrying the same command id stayed closed. No token is recorded here.
