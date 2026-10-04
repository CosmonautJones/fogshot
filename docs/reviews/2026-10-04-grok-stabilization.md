# Fogshot: independent review and stabilization handoff

Date: 2026-10-04

## Read this before changing anything

This is an **update to the existing implementation**, not a replacement bootstrap,
new architecture, or instruction to start over.

Reviewed repository: `CosmonautJones/fogshot`.
Reviewed branch: `cursor/first-playable-66d6`.
Reviewed commit: `36e8a5321d216ac3e153ba7e5fcad92e9290ef70`.
At inspection, draft PR #1 targeted `main`; `main` was still bootstrap commit
`3d445ed3e2c8e61e22ddfa8891b5cae44773bce1`.

The bots may already have newer work. Fetch, inspect current status, and reconcile
these findings with the current branch before editing. Do not reset, force-push,
replace current files with the old bootstrap, or duplicate an already-fixed task.

### Evidence and confidence

This review inspected source, test definitions, the PR description, and build
notes through the GitHub connector. It did **not** execute Jac, rerun the game
suite, reproduce the browser sessions, or access the screenshots on the builder's
machine. The recorded `36 passed` is the builder's reported result, not an
independently rerun result. GitHub Actions returned zero runs at inspection.

The observations below distinguish source-confirmed behavior from scenarios that
still require runtime reproduction. They are not claims of a completed security
audit or a CodeRabbit result. No gameplay fix is included in this documentation
patch, and no remote branch has been updated by the reviewer.

## Grade and what to preserve

**B / roughly 7 out of 10 as an early technical prototype. Not release-ready.**
This is a judgment about the evidence, not a measured quality score. Fun, balance,
visual polish, and deployment reliability remain ungraded without direct play.

There is meaningful implementation here: Jac match rules, a Jac supply walker,
Pymunk-driven shots, per-player view projection, a two-seat match, objective
outcomes, rematch, and restart/retry tests. Keep the Jac-first direction. Do not
rewrite in Unreal, Godot, or a JavaScript-first game as a response to this review.

The key qualification: a carefully tuned miniature fixture with one core per side
is a useful technical proof, but it does not yet validate the spatial-memory game
or the four-objective infrastructure economy.

## Gate 1: correct the authority boundary before public deployment

### F01. Reveal authorization trusts client time — release blocker

**Source:** `server/live.jac`: `loose_shot`, `watch_match`, `take_shot`,
`_reveal_on`, `_encode`, and `join_seat`.

The HTTP functions accept `now_ms` from the client. `_reveal_on` sets the expiry
from that value, and `_encode` decides whether the reveal is open by comparing the
client-supplied time with the stored expiry. `join_seat` also calls `watch` with
zero rather than authoritative current time.

**Consequence inferred directly from the comparison:** after a real reveal expires,
a caller can supply an earlier time and make the server treat it as open again
while that reveal remains assigned to the same seat. A future timestamp on a shot
can also extend its recorded deadline. This is not just local removal of a fog mask.
Reproduce through the real protected endpoints before marking the fix verified.

**Required change:** use a server-owned clock for every authorization decision.
Keep an injectable clock in internal tests, not a caller-controlled HTTP clock.
Remove or ignore client time as an authority input. Apply this to join, polling,
shot, retry, reconnect, and rematch responses. Coordinate review duration with
server-owned playback phases; do not let network loading silently consume it or
let an unbounded client acknowledgment hold the match indefinitely.

**Adjacent leak:** `_encode` exposes the post's `broken` and `angle` whenever any
reveal is open for A, even if the post lies outside that patch. Derive exposed
object fields from the actual authorized projection, not a generic `opened` flag.

### F02. The live API cannot reject a client's stale intended turn — high priority

**Source:** `server/live.jac`: `take_shot`, `_same_shot`, `_stored`;
`server/authority.jac`: `submit`; `client/battlefield.jac`: `_release`.

The lower-level `submit` accepts revision and turn, but `take_shot` fills them
from the server's current values. The HTTP command has no expected turn/revision
or match epoch from the player's last view. Testing `submit` directly with a stale
revision does not verify freshness at the browser/API boundary.

Weapon identity is inferred again from the current phase before `_same_shot`.
A successful recon-flare retry after the transition to combat can therefore be
compared as a shell and rejected as a conflict. The client also creates a new
command id for every release, with no pending-command retry protocol.

**Required change:** define one immutable command envelope shared by client and
server: match id/epoch, command id, expected turn, expected revision, weapon, and
bounded launch intent. Return the current epoch/turn/revision to the client.
Check authenticated seat ownership, then handle an exact cached retry against
its original intent before evaluating a fresh command's turn eligibility.
Reuse the same command id after uncertain delivery. A changed intent on that id
must conflict. A delayed new command must not become valid just because it is
that seat's turn again. Rematch changes the epoch.

Store a stable command receipt and authoritative outcome. Returning that receipt
must not re-authorize expired reveal contents; response projection still uses
current visibility rights.

### F03. Command commitment precedes physics resolution — release blocker

**Source:** `server/authority.jac`: `submit`, `_append_commit`;
`server/live.jac`: `take_shot`, `_launch`, `_replay`;
`physics/pymunk_driver.jac`: `capture`, `restore`, `hurt`.

The source order is `submit -> update rules/journal -> clear in_flight -> _launch`.
The persisted record contains shot inputs and rule metadata, not the resolved
physical outcome. The journal writer rewrites the existing file with
`Path.write_text`. Restart reconstructs the world by simulating past inputs again.

This creates failure windows between accepted turn and resolved world. The
`in_flight` flag does not cover physics. Actual concurrent interleavings depend
on the runtime and must be reproduced, not assumed. A pre-commit test flag in
`submit` does not exercise a failure inside `_launch` or during a real file write.

**Required change:** one match transaction must cover validation, simulation,
rule/supply/victory updates, and durable commitment before the next turn is exposed.
Use a real per-match synchronization mechanism and explicitly constrain the first
deployment to its supported worker model. Choose the smallest transactional
store that works, such as SQLite through a narrow server-side adapter; record the
choice. Do not add Redis, a queue, or a service fleet just for this slice.

Persist a versioned authoritative snapshot and command receipt together. Include
body poses/velocities, collider and joint state, health/aliveness, rules, supply
state, match epoch, and the information needed for filtered playback/recovery.
On a failed uncommitted shot, restore the complete prior state; after a committed
shot whose response was lost, a retry must not simulate again. Restart must not
require replaying every historical input to obtain the latest canonical state.

**Restoration detail to test:** `hurt` removes a destroyed core's shape, while
`restore` restores fields but does not visibly re-add that shape. A restored core
must be collidable, not merely report `broken = false`. Rebuilding the world from
a complete snapshot is acceptable if it is simpler and tested.

### F04. Prototype authentication and room lifetime need a deployment boundary

**Source:** `client/battlefield.jac`: shared `PASSWORD`, `_email`, `_join`;
`server/live.jac`: singleton `_shared`, fixed invite, `shared_match`;
`server/authority.jac`: seat persistence.

The browser registers generated email identities using one public password.
The random email is not a license to treat this as production authentication;
knowledge of an identity plus the public password would permit login. This review
has not demonstrated disclosure of another player's generated identity.

There is one global match with one fixed invite and persistent seats, rather than
independent private rooms. These are explicitly acceptable local-fixture shortcuts,
not a public matchmaking design.

**Required before public play:** proper isolated guest/session credentials or a
supported authentication flow; server-issued unpredictable room invitations;
room-scoped state and membership; bounded abandon/resume handling; explicit
room/full/expired feedback. Do not log credentials or add captured session data
to this public repository. Room isolation is tested with two simultaneous matches.

## Gate 2: prove Fogshot's actual memory-and-destruction loop

### F05. Ground misses and flares do not provide the specified information

**Source:** `server/live.jac`: `_reveal_on`; `physics/pymunk_driver.jac`:
`ensure`, `add_ground`, `simulate`; `tests/qa_match_tests.jac` miss assertion.

Reveals are triggered by contact with a short named-object list. The collision
callback shown is projectile/structure, not projectile/ground. The miss test
currently asserts that there is no reveal. The game spec instead calls for a
local first-impact reveal on terrain as well as structures, and a larger
non-damaging flare patch.

Record the actual first impact position and simulation time, including terrain.
Do not center the patch on a named body's final settled position. A flare landing
on empty terrain must scout that location. Update the conflicting test to verify
the intended information policy, not simply preserve the current behavior.

### F06. Structural damage and supply are still a demonstration fixture

**Source:** `physics/pymunk_driver.jac`: collision registration and `hurt`;
`server/live.jac`: `_arm`, `_apply_hit`, `_powered`;
`graph/supply.jac`: `PowerWalk` and `assess`.

Only projectile/structure contacts are registered for damage. Falling supports
can move, but the shown damage path does not implement structural crushing from
body/body contacts. The live supply chain changes a lamp; it does not yet change
recharge, scouting, or another useful capability. Only B has the physical supply
post in this fixture, and its core is placed for scripted test shots, not a
validated symmetric opposing outpost layout.

Next build two reachable small outposts with real supports, a core per side for
the narrow experiment, and a physical link on each side. Make one falling piece
capable of damaging a core or severing a route. Gate impact damage to avoid idle
settling destroying everything or counting a persistent contact every tick.
Add one modest, understandable connected-supply perk while preserving free basic
shots. Retain the agreed four-objective rules as the subsequent game milestone;
do not quietly redefine the full game to one core.

### F07. Playback and controls need to represent what the server simulated

**Source:** `client/mount_field.js`: `update`, `apply`, pointer handlers;
`server/live.jac`: `_encode`, `watch`; `client/battlefield.jac`: `_poll`, `_release`.

The shooter gets a sampled path; polling returns an empty path. The renderer
advances one sample per render frame rather than using sample times. Body views
are final poses, not a collapse timeline. This means the source does not establish
a shared, correctly timed shot-and-collapse presentation for both participants.
The pointer adapter also lacks the tested domain helper's full cancel/ownership
logic, and the canvas is fixed-size. Do not equate helper tests with live input tests.

Deliver a bounded, timestamped, per-player filtered event/frame sequence to both
participants. Interpolate with elapsed time; do not run a second authoritative
physics simulation in Phaser. Reveal around the impact stage, not at request
submission. Handle cancel, pointer ownership, release outside the canvas,
resize/touch, and out-of-order poll responses. A shot receipt and scene revision
must prevent a late poll from overwriting newer state.

## Gate 3: make the evidence portable, then deploy the thin slice

Keep the actual browser test scripts, not only prose describing their results.
Automate a clean Jac test run, client build, and a small two-context browser smoke
check. At inspection there was no GitHub Actions run to independently establish
these checks. Use change-scoped/manual browser runs and cancel superseded runs to
avoid unnecessary CI use. Store sanitized artifacts, not builder-local paths only.

Target JacHammer as planned, but first verify the pinned toolchain, native physics
import, persistence, protected functions, HTTPS guest flow, and supported worker
model on that host. Do not label a local `jac run` proof as deployed. Credentials,
new purchases, or expanded access require the owner's approval; no secrets in chat.

Once the two-person loop is reliable, test with people who did not build it. Ask
why they adjusted the second shot, what they learned from a miss, and whether they
want a rematch. Do not grade fun from commit counts or passing unit tests.

## Integration and scope

One lead owns integration, `server/live.jac`, shared contracts, and BUILD-STATUS.
A reviewer writes/reproduces regressions in an isolated worktree. Avoid concurrent
edits to the same match coordinator. No broad rewrite, unrelated repository work,
rankings, monetization, large arsenal, or full map editor during stabilization.

Commit/push each coherent verified fix to the agreed feature branch. Never merge
the draft PR merely because this review packet was accepted. Report findings as
fixed only with a reproducing red test, green test, and current suite evidence.

Read `2026-10-04-grok-acceptance.md` for the ordered acceptance checks.

## Pinned source references

- [server/live.jac](https://github.com/CosmonautJones/fogshot/blob/36e8a5321d216ac3e153ba7e5fcad92e9290ef70/server/live.jac)
- [server/authority.jac](https://github.com/CosmonautJones/fogshot/blob/36e8a5321d216ac3e153ba7e5fcad92e9290ef70/server/authority.jac)
- [server/views.jac](https://github.com/CosmonautJones/fogshot/blob/36e8a5321d216ac3e153ba7e5fcad92e9290ef70/server/views.jac)
- [physics/pymunk_driver.jac](https://github.com/CosmonautJones/fogshot/blob/36e8a5321d216ac3e153ba7e5fcad92e9290ef70/physics/pymunk_driver.jac)
- [client/battlefield.jac](https://github.com/CosmonautJones/fogshot/blob/36e8a5321d216ac3e153ba7e5fcad92e9290ef70/client/battlefield.jac)
- [client/mount_field.js](https://github.com/CosmonautJones/fogshot/blob/36e8a5321d216ac3e153ba7e5fcad92e9290ef70/client/mount_field.js)
- [graph/supply.jac](https://github.com/CosmonautJones/fogshot/blob/36e8a5321d216ac3e153ba7e5fcad92e9290ef70/graph/supply.jac)
- [tests/qa_match_tests.jac](https://github.com/CosmonautJones/fogshot/blob/36e8a5321d216ac3e153ba7e5fcad92e9290ef70/tests/qa_match_tests.jac)
- [docs/GAME-CONCEPT.md](https://github.com/CosmonautJones/fogshot/blob/36e8a5321d216ac3e153ba7e5fcad92e9290ef70/docs/GAME-CONCEPT.md)
- [docs/BUILD-STATUS.md](https://github.com/CosmonautJones/fogshot/blob/36e8a5321d216ac3e153ba7e5fcad92e9290ef70/docs/BUILD-STATUS.md)
- [jac.toml](https://github.com/CosmonautJones/fogshot/blob/36e8a5321d216ac3e153ba7e5fcad92e9290ef70/jac.toml)

PR inspected: https://github.com/CosmonautJones/fogshot/pull/1
