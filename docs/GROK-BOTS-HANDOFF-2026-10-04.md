# Fogshot: Grok Bots hardening and first-playable handoff

Date: 2026-10-04
Status: Actionable follow-up work; implementation and new runtime verification remain with the active builders.
Reviewed baseline: PR #1, `cursor/first-playable-66d6`, commit `36e8a5321d216ac3e153ba7e5fcad92e9290ef70`.

## Start here

Continue the existing Jac-first project. Do not restart from the bootstrap, rewrite the game in another language, or replace newer work with this reviewed snapshot. Fetch current refs and read the latest PR #1 discussion, AGENTS.md, README.md, docs/GAME-CONCEPT.md, docs/FIRST-PLAYABLE.md, docs/BUILD-STATUS.md, and the Jac-first ADR before changing code.

This handoff is documentation only. Its source findings were inspected in GitHub; the reviewer did not rerun Jac tests, play the build, or reproduce a deployed exploit. The baseline PR reports 36 local tests and two-browser checks. The baseline check-runs endpoint returned zero checks. Treat reported local results, independent reproduction, CI, and deployment as different evidence categories.

If a finding is already fixed on the current branch, demonstrate the regression test and cite the fixing commit instead of implementing it again. If it does not reproduce, document the precise reason and evidence. Do not change code just to agree with the review.

## Work queue

| Order | Issue | Required result |
| --- | --- | --- |
| 1 | [#2: Server-owned reveal time](https://github.com/CosmonautJones/fogshot/issues/2) | No caller timestamp or join/retry path can revive expired visibility. |
| 2 | [#3: Live command contract](https://github.com/CosmonautJones/fogshot/issues/3) | Expected turn/revision and match generation reach the real endpoint; retries remain safe across phases. |
| 3 | [#4: Recoverable shot transaction](https://github.com/CosmonautJones/fogshot/issues/4) | Physics outcome, graph/rules, command receipt, and next turn commit consistently and survive failure/restart. |
| 4 | [#5: The blind-memory gameplay loop](https://github.com/CosmonautJones/fogshot/issues/5) | Useful miss feedback, equivalent opportunities for both seats, and readable time-based collapse playback. |
| Alongside 1-4, then preview | [#6: Reproducible verification and safe hosting](https://github.com/CosmonautJones/fogshot/issues/6) | Committed HTTP/browser tests and CI; safe session/room handling before a verified JacHammer preview. |

The linked issues contain the source observations, expected behaviors, and regression acceptance. They are the implementation checklist, not an invitation to start another architecture proposal.

## Preserve the good parts

Jac continues to own match rules, input validation, infrastructure connectivity, authority, and visibility policy. Phaser renders entitled observations. Pymunk remains the first server-side solver. Keep justified interoperability adapters documented and the working toolchain pinned. No LLM calls decide shots, damage, or victory.

Keep the milestone small: two players, one objective per side, opening reconnaissance, free basic shots, one meaningful physical support/supply connection, victory, and rematch. The existing supply lamp is an explicitly scoped proof; a full strategic economy is not required by this handoff.

Do not add rankings, monetization, extra weapons, procedural worlds, a freeform editor, an engine migration, or distributed infrastructure to avoid fixing the present boundaries.

## Gate A: Authority is trustworthy

Complete #2, #3, and #4 as small sequential slices. One lead owns the overlapping authority files.

The server owns its clock. Tests may inject a private clock, but network payloads must not control permission expiry. Audit polling, join, retry, error, reconnect, and rematch paths, not just the successful shot response. A previously delivered observation cannot be erased from a player's memory; the promise is that expired permissions cannot fetch additional live hidden state.

Use a stable command contract carrying match identity/generation, command ID, expected turn/revision, explicit weapon, and bounded aim data. Derive seat ownership from the session. Do not fill in the client's expected version with the latest server version. Exact retries must remain idempotent after phase changes, finishing, or restart, and must not replay expired private views. Old-generation commands must not mutate a rematch.

Serialize validation, simulation, rule/graph consequences, durable outcome commit, and publication. Rematch participates in the same authority boundary. Restore committed resolved state rather than silently depending on physics re-simulation to reconstruct it. Demonstrate failures before/during simulation, around storage writes, and after commit but before the response. Validate collider/constraint restoration as well as JSON flags. A single explicitly enforced worker and a small local transactional store are sufficient for this milestone.

**Gate evidence:** failing regressions followed by passing fixes, actual HTTP-boundary tests, concurrent submissions, failure injection/restart/retry results, hidden-data checks, and pushed commit SHAs. A manually set busy flag or a direct pure-function call alone does not prove the live boundary.

## Gate B: The duel communicates what happened

After Gate A, complete #5. Ordinary empty-ground impacts and flares must teach the player something through bounded local feedback; do not reveal only when a hardcoded named target is hit. Both seats need reachable supported objectives and a legal winning scenario.

Play back flight, impact, break, fall, and aftermath using timestamped entitled events/keyframes. Avoid showing final destruction before the displayed projectile arrives. The defender needs its authorized sequence too. Interpolate by elapsed time, not one sample per rendered frame. Filter private bodies, dimensions, seeds, link data, and off-patch effects before transmission.

Coordinate the bounded review window with server authorization. Handle low frame rate, delayed/out-of-order polling, background tabs, and reconnect. A client cannot hold visibility or the turn open indefinitely.

**Gate evidence:** committed two-context browser automation plus a redacted recording of an intentional miss-correct-hit-collapse, both-seat win cases, rematch, and privacy checks. Measure release-to-feedback latency and payload size. Then seek a small human playtest; observations about informed aiming and the desire to rematch are useful, but passing assertions do not prove fun.

## Gate C: Reproducible, limited preview

Start #6's verification tooling in parallel where file ownership permits. Check the installed pinned toolchain for valid commands. Commit the actual browser/HTTP tests, a clean-checkout verification entry point, and modest CI with minimal permissions, timeouts, and concurrency cancellation. Do not copy a prose test count into a green badge.

Before any public preview, replace shared-password demo sessions, verify membership and refresh/reconnect, document the limited room/seat lifecycle, and enforce the supported worker topology. Test JacHammer's real runtime, native dependency support, persistence, and authentication using already-authorized access. No new purchases, permission expansion, or paid infrastructure are authorized by this handoff.

An unavailable hosting credential does not stop local correctness or gameplay work. Report the exact blocker. A hosted claim requires an actual URL exercised with two sessions at the named deployed commit.

## Bot coordination and Git discipline

- **Lead:** owns integration, command/view contracts, `server/live.jac`, `server/authority.jac`, `server/views.jac`, related rule changes, and final commits to the active implementation branch.
- **QA/reviewer:** uses an isolated worktree for endpoint/failure cases, browser automation, and CI. Agrees on interfaces before implementing dependent tests. Reports evidence rather than editing the lead's files concurrently.
- **Presentation worker, optional:** owns the renderer adapter only after the server event contract is agreed. No independent physics authority and no unrestricted hidden-world payloads.

Inspect current branches and uncommitted work before switching. Adopt this documentation through a docs-only cherry-pick/integration or read it directly; do not reset the active branch to the handoff branch. Preserve published history. No force-push, branch deletion, blind merging, or changes to unrelated repositories. Keep PR #1 open/draft until its implemented scope has the corresponding evidence; this handoff does not merge or approve it.

Commit each coherent verified slice and push promptly. Before committing, inspect the diff, run `git diff --check`, inspect for secrets/private artifacts, and run relevant checks. Keep credentials, tokens, runtime databases, and unredacted authenticated captures out of Git.

## Report after each completed slice

Update the top of docs/BUILD-STATUS.md with the current source SHA, what actually works, exact verification commands and results, local/CI/browser/deployed evidence categories, limitations, and the next bounded task. Reconcile checked items in docs/FIRST-PLAYABLE.md with real coverage. Link detailed logs/recordings without exposing private data.

Reply on the relevant issue with the fixing commit and test evidence. Do not close work merely because it was described in documentation. Integration into the active feature branch and eventual merge to main are separate events; do not equate a docs PR merge with a gameplay fix.

**Next concrete deliverable:** the server-clock regression and fix in #2, followed by the endpoint contract in #3. Keep building; do not restart planning.
