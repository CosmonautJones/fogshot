# Moonlit outpost visual polish — 2026-10-14

One bounded presentation slice on `codex/fogshot-moonlit-polish-20261014`, based on `81bb802433a9049b23c80af8e82433aff6e4b953`. Server rules, physics, payload projection, room authority and persistence are unchanged. No merge or deployment was performed.

## Result

The Jac page now presents an original layered moonlit landscape, material-clad cores/supports, a mechanical launch platform, restrained projectile glow and a finite observation pulse. The responsive HUD separates initiative, projectile, supply and objective status; instructions and keyboard controls are visible outside the canvas. Rematch is enabled only after the duel finishes.

Input remains in the 800×400 logical arena. B's natural right-side pull is converted once into the existing mirrored server protocol. The small direction cue uses the local pull only; it predicts no landing or hidden collision. Actual flight and collapse still sample the server result. Own infrastructure remains visible even across the midpoint. Enemy artwork uses the supplied clipped dimensions, and observations expire by wall time even if polling fails or a tab resumes. Touch cancellation, additional pointers, outside release, Escape, blur and input-mode changes cancel cleanly.

## Design and assets

Original editable art and provenance: [assets/README.md](../assets/README.md). No external game-art pack, traced asset, raster-generated text, logo, font download or commercial reference-game asset is included. The repository's distribution-license decision remains open. Phaser 3.90.0's installed `LICENSE.md` and package metadata identify its existing MIT license; no new rendering dependency was added.

Claude Code 2.1.296 completed one bounded design critique with tools, customizations, browser and session persistence disabled. Native `modelUsage` metadata reported `claude-sonnet-5-5`. The first sandboxed attempt failed DNS before inference; the authorized network retry completed. We adopted the moonlit palette, illustrated machinery and compact HUD, and omitted persistent scorch decals and ambient motion. Gemini was unavailable: no installed `gemini` CLI or callable Gemini tool was exposed. No Gemini-generated asset is claimed.

The SVG is 2,515 bytes, SHA-256 `afc3d39fb3bc7a5e720082750e890d53ca35147d4ce8fef62f8494d58fd9c05f`. Phaser rasterizes it once at mount. Fog is generated once. Optional effects use at most ten dots plus a ring for 0.8 seconds; reduced motion removes that pulse/dots and projectile glow. There is no camera shake or continuous ambient animation.

## Verification

- `jac check main.jac client/battlefield.jac`: passed; existing interop/explicit-any/JSX-name warnings remain.
- `jac build`: final source passed, 11/11 server modules compiled, six client dist files, sealed output 3,743,652 bytes (including the retained evidence files). The supported root `assets/` path and direct Jac import of `presentation.js` are required; the first build exposed and then fixed the missing transitive CSS/SVG staging.
- `JAC_TEST_STRICT=1 jac test tests/*_tests.jac -v`: **50 passed in 40.64s**, including privacy, duplicate/conflicting commands, wrong actor/turn/revision, transaction recovery, thin supports, bounded settling, supply, both winners and restart/rematch behavior. Authoritative Jac files were not changed afterward.
- `node --test tests/playback_client.test.mjs tests/room_client.test.mjs tests/presentation_client.test.mjs`: **14 passed**. The new presentation file first failed with the intended missing-module error before implementation.
- `node tests/e2e/shot_race.mjs`: **shot race ok**. One simultaneous command was accepted, the other returned busy, and a separate room stayed untouched.
- `node tests/e2e/two_seats.mjs`: **two seats ok**. Two real isolated browser sessions, B's physical pull mapping, filtered responses, reveal closure, supply loss without losing shell access, A and B wins, stale-epoch rejection and shared rematch.
- `node tests/e2e/presentation.mjs`: **presentation interactions ok**, zero page errors. Real Jac application; no response stubs. Checks 1280px/390px fit, CDP touch cancellation/additional touches, outside release, keyboard-to-pointer switching, exact scaled pull coordinates, keyboard launch, reveal expiry with watches blocked, and reduced-motion reload.
- `git diff --check`: passed. Built client and source maps omit the existing hidden-state sentinels and obvious credential markers checked in this pass.

The browser test originally attempted an illegal mid-match rematch and was corrected to open a fresh room. Its viewport test also now refreshes the canvas box after focus/capture operations and asserts the actual logical pointer coordinates before firing. The final focused run passed; a prior run without those safeguards timed out. It is not recorded as a gameplay pass.

Independent code review requested and verified fixes for B input, touch cancellation, keyboard/pointer switching, expiry on background/resume, stale reveal datasets and caption assertions. Final source review reported no remaining blockers. Independent screenshot review led to minimum mobile label sizing, two-line objectives and quieter fog. Screenshots alone do not establish gameplay or production readiness.

## Measurements and evidence

The final local dev run reached an entitled seat at 976.3 ms, with no horizontal overflow. The 120-frame effect sample measured 16.7 ms median / 16.8 ms p95; reduced-motion idle measured 16.7 / 16.8 ms. These are local headless desktop Chrome measurements while other work was active, not physical mobile or hosted performance guarantees. The full metric record lists dev resource transfers separately from production bundle sizes.

At the visual evidence checkpoint, production client JS was 2,175,109 bytes (527,523 gzip), CSS 4,675 bytes (1,636 gzip), SVG 2,515 bytes (1,049 gzip). Gzip figures are local compression measurements, not a claim that a hosted server serves gzip. Existing framework/renderer weight dominates. No external asset request is required.

[Evidence gallery](evidence/2026-10-14-visual-polish/README.md) records the pushed implementation checkpoint `0306e1d8e124ba9360ca8f6432069c6a40a57edc`. Room codes and the dynamic caption are redacted from public captures; no JWTs, seat tokens, match databases or raw network traces are included. The before image is the **original renderer with a synthetic entitled observation fixture**; after images are the actual Jac game, including aiming/reveal states.

## Runtime limits and reproducibility

All new project, tool, asset and evidence files live on X:. The installed Windows Jac was 0.16.7 and was not changed. The official Linux 0.37.23 executable was checksum-verified (`2c3c697616b08516caf01704571e7e7020f4b294cd2bef7f04e8ef1ceec9d6ad`). Ubuntu's filesystem is backed by `X:\WSL\Ubuntu`; its isolated `/var/tmp/fogshot-moonlit-*` caches avoid slow extraction on the Windows mount. Existing TravOS workers and browser sessions were left alone.

Working source command in that isolated environment:

```sh
XDG_CACHE_HOME=/var/tmp/fogshot-moonlit-cache \
XDG_DATA_HOME=/var/tmp/fogshot-moonlit-data \
TMPDIR=/var/tmp/fogshot-moonlit-tmp \
/mnt/x/Projects/fogshot-polish-control/bin/jac run --dev --host 127.0.0.1 --port 8180 --api-port 8181 --workers 1
```

Browser checks were run with Windows Node, the X:-local Playwright 1.55.1 installation, `FOGSHOT_BROWSER_CHANNEL=chrome`, `FOGSHOT_URL=http://127.0.0.1:8180/`, and `FOGSHOT_API=http://127.0.0.1:8181`. `scripts/verify.sh` registers the new Node and browser tests for the normal clean-checkout workflow.

An earlier `jac run dist/fogshot.jab` attempt failed with `Sealed application is missing executable artifact: .../main.jac`. The sealed launch path has **not** been qualified. The tested deliverable is the source/dev workflow. An initial source startup also rejected a source change during preparation; startup was repeated with edits paused. No hosted, sealed-package, human-playtest, low-end physical-device or production-ready claim is made.

Rollback: revert the feature commits or leave the branch unmerged. Main and existing WIP were not edited. Merge and deployment still require specific Fogshot approval.

## CI boundary-race follow-up

The first remote Linux verification (`38656644667`, implementation checkpoint `0306e1d`) passed all Jac/Node tests and the HTTP race, but caught a transient expired observation: `reveal` was closed while A's `broken` dataset was briefly restored by a delayed open-poll response. The next poll cleared it. The subsequent unmodified evidence head `d8f1ca3` passed the full Linux verification (`38656913178`), confirming the timing-dependent nature; that pass does not excuse the race.

The follow-up adds `observationAt` before playback and HUD bookkeeping, using one captured wall timestamp for all response-expiry decisions. It strips expired bodies, paths, collapse state and A's enemy-post break/angle together; B retains the same post's own-state fields, as defined in `server.live._encode`. Local closure likewise preserves entitled own state. A new deterministic regression failed before the helper existed and then passed; the focused Node total is now 14. No server projection, physics or rules were changed. Screenshots remain an accurate record of the earlier visual checkpoint; this repair changes expiry bookkeeping rather than art.

The independent follow-up review caught and repaired a second boundary case where two separate clock reads could straddle expiry. A time-advance regression covers the explicit cutoff. Preparation is now run with all repository edits paused; the runtime fingerprints documentation as well as source, so an earlier concurrent report update caused a safe preparation abort.

The frozen expiry-repair revision also passed `jac build` (11/11 modules; 3,743,652-byte sealed output). The sealed launch path remains unqualified; no packaging-start success is inferred from build success.

Both final code-checkpoint Linux verification runs passed on `4d40b8cd9756203ee90945608b66f79895647731`: [push verification](https://github.com/CosmonautJones/fogshot/actions/runs/38657552634) and [PR verification](https://github.com/CosmonautJones/fogshot/actions/runs/38657598866). These ran the registered complete verification entry point, including all 50 Jac tests, all 14 Node tests, the HTTP race, both-seat game flow and presentation interactions. The subsequent README/report alignment changes documentation only.
