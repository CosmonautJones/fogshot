# Fogshot stabilization acceptance checks

Date: 2026-10-04
Review baseline: `36e8a5321d216ac3e153ba7e5fcad92e9290ef70`.

**Status: proposed checks, not tests executed by the reviewer.** Add tests using
the current runtime and API, observe the intended failure before each fix, and
record the result. A dependency/import failure is not reproduction of a game bug.
Do not replace an existing better test with a weaker check from this list.

## 0. Reproduce the existing baseline

Fetch the current feature branch and inspect uncommitted work before changing it.
Run the existing documented baseline, adapting only to verified later renames:

```sh
JAC_TEST_STRICT=1 jac test \
  tests/physics_driver_tests.jac \
  tests/scene_host_tests.jac \
  tests/aim_rules_tests.jac \
  tests/siege_view_tests.jac \
  tests/authority_tests.jac \
  tests/supply_tests.jac \
  tests/live_match_tests.jac \
  tests/outcome_tests.jac \
  tests/qa_match_tests.jac -v
```

The old build notes say 36 passed. Record the actual current result, versions,
source commit, and exact command. Do not assume the count is still 36. Preserve
existing in-progress changes and stop destructive operations, not ordinary work.

## 1. Authority and hidden information

| ID | Setup and action | Required result |
|---|---|---|
| A01 | Open a real reveal, advance an injected server clock past expiry, and call the protected watch endpoint with omitted, zero, past, and far-future client time fields. | Expired geometry stays hidden. Client time is ignored or rejected as an authority input. |
| A02 | Submit with a far-future client timestamp and inspect the server's reveal deadline. | The deadline is bounded by the server policy, not the submitted timestamp. |
| A03 | After expiry, rejoin, refresh, reconnect, retry the shot, and poll. | None resurrects expired live geometry. A stable receipt does not bypass current projection. |
| A04 | Open a reveal far from the enemy post, with the post explicitly outside the patch. | Payload summaries, captions, and debug fields do not disclose that post's angle or damage state. |
| A05 | Use randomized private markers for each seat; inspect full authenticated responses, errors, reconnection and playback payloads for both A and B. | Only own/public/explicitly authorized revealed data is present. Do not rely solely on the old fixed sentinel strings. |

At the reviewed source, `watch(live, player, 0)` after a positive reveal deadline
illustrates the F01 comparison flaw, but a definitive regression must cross the
HTTP boundary with a controlled server clock. Calling a test helper with a fake
time alone does not establish that the production endpoint is fixed.

## 2. Command intent, retries, and rematch isolation

| ID | Setup and action | Required result |
|---|---|---|
| C01 | Accept A's recon flare, accept B's recon flare so combat begins, then resend A's identical original command. | Same receipt/accepted intent, no conflict from weapon re-inference, no new shot or resource spend. |
| C02 | Reuse a command id with changed weapon, angle, power, or epoch. | Conflict or wrong-epoch rejection; zero new simulation. |
| C03 | Delay an unseen A command captured at revision r until A is eligible again at a later revision. Submit through the public endpoint. | Stale rejection, not automatic acceptance using the server's latest revision. |
| C04 | Drop a successful response and retry using the same pending client command id. | Exactly one durable resolved shot; client reconciles with that receipt. |
| C05 | Rematch, then deliver a delayed command from the previous match epoch. | Rejected without moving a body, advancing a turn, or revealing either layout. |
| C06 | Deliver two requests simultaneously under the supported real server runtime. | No overlapping world mutation and at most one accepted resolution for that turn. Capture real evidence rather than just setting an in_flight flag in a unit test. |

Freshness and idempotency must be checked on the actual HTTP command path, not
only by direct calls to `submit`. Authenticate before accessing cached commands.
Keep receipt identity stable while applying current visibility filtering.

## 3. Durable shot transaction

| ID | Injected failure or restart | Required result |
|---|---|---|
| D01 | Fail after validation but before simulation starts. | Previous settled match and turn remain usable, lock released. |
| D02 | Fail after a partial physics mutation but before durable commit. | Restore bodies, joints, colliders, health, supply, rules and command history together. |
| D03 | Fail a storage write/commit at the real storage seam. | Either the old complete state or new complete state survives, never a truncated canonical journal or half-shot. |
| D04 | Commit successfully but lose the response, then restart and retry. | Restore the saved resolved state; no second simulation/damage. |
| D05 | Restart a finished match with a collapsed post, severed route, and dead core. | Exact canonical result restored from persisted outcome/snapshot, not dependent on replaying historical inputs. |
| D06 | Capture an intact core; destroy it so its collider is removed; restore and hit it again. | Restored core physically collides and can be damaged. Restored flags alone are insufficient. |
| D07 | Force an exception while resolving; then submit an allowed subsequent command. | No stuck busy flag and no uncommitted advancement. |

Pin snapshot schema and solver version. If a stored version cannot be restored,
reject or migrate explicitly; do not silently create a fresh match under old seats.
Document and enforce the supported deployment worker count before testing scale.

## 4. Real memory-loop behavior

| ID | Scenario | Required result |
|---|---|---|
| G01 | A shell misses structures and first hits terrain. | Small local patch centered on that first impact; useful miss feedback; no distant leak. |
| G02 | A flare lands on otherwise empty terrain. | Larger local scouting patch, no direct damage, then expiry. |
| G03 | A hit moves the target during settling. | Reveal is anchored to the impact position, not silently relocated to the body's final pose. |
| G04 | Break a load-bearing support; falling mass contacts another structure/core with no projectile contact on the victim. | Bounded, intentional secondary damage can occur. Idle resting contact does not repeatedly drain health. |
| G05 | Disconnect a physical route on each side; test an intact alternate route. | Connection and one actual perk update correctly, alternate route works, basic shots remain available. |
| G06 | Inspect both outpost placements and launch envelopes. | Comparable reachable objective regions; not only hand-tuned shots that let A win a fixture. |
| G07 | Repeat a shot against unchanged state, then against newly placed rubble. | Learnable flight; changed physical geometry can alter the outcome without random aim spread. |

Use the spec as the authority. The reviewed test asserting no reveal for a ground
miss must change when G01 is implemented. Do not make a wrong test green by
removing the intended mechanic from the design.

## 5. Browser presentation, inputs, and network ordering

| ID | Scenario | Required result |
|---|---|---|
| B01 | Two independent browser contexts observe a shot/collapse at 30, 60, and 120 render frames per second. | Comparable timeline duration and same authorized outcome; no one-sample-per-render-frame speed dependence. |
| B02 | Add transport delay and out-of-order polling around a shot. | Older revisions do not overwrite newer state; the player receives the bounded intended reveal/review period. |
| B03 | Cancel drag, add a second pointer, release outside the canvas, resize, and use touch. | No unintended attack, no duplicate shot, stable world-space aim and a clear cancel route. |
| B04 | Try to fire while unseated, while the opponent acts, while resolving, and after victory. | Input affordance communicates state; the server still rejects illegal requests. |
| B05 | Rematch and reconnect after a displayed projectile/collapse. | Clear stale projectile/path/scene state; preserve correct seat and match epoch. |

Commit executable browser tests. Save short sanitized recordings of the ordinary
miss, recon, support collapse, supply consequence, both-client result and rematch.
A dataset flag or screenshot alone does not prove animation or network ordering.

## 6. Hosting-readiness gate

Replace the shared browser password with an appropriate isolated session flow.
Prove two independent rooms cannot read or mutate one another and that abandoned
seats have a bounded lifecycle. Add repeatable checks in CI without unnecessarily
running a heavy browser suite on every documentation-only push.

Only then exercise the same slice on JacHammer: dependency import, protected
routes, persistent state, HTTPS sessions, restart, and worker restrictions. Report
an exact blocker if access is unavailable. Do not buy hosting or broaden access
without approval. A localhost URL is not deployment evidence.

## Review-complete report required from the lead bot

For each finding: reproduced / fixed / already fixed / deferred, with the reason,
source commit, regression test, actual command/output and pushed SHA. Identify
remaining gaps. Distinguish local evidence, CI evidence, and deployed evidence.

Next product proof: a newcomer explains an informed second shot and deliberately
breaks a support or route, then completes a duel and elects to rematch. Record
observations; do not claim retention or balance from a handful of tests.
