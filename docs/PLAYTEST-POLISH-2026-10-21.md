# Playtest and game-feel pass - 2026-10-21

Branch `polish/playtest-pass`, based on main `1ac71b9`. Presentation and client-flow only: no change to server authority, physics, practice bot, hidden-data projection or dependencies.

## How it was played

Pinned Jac 0.37.23 (`jac install`, `jac run`, app on :8000). `qa/playtest.mjs` drives real practice matches with Playwright 1.55.1 headless Chromium, at 1280x800 (mouse) and 390x844 (CDP touch drags, DPR 2): two full rounds each (flare, bot reply, shells until a result, Rematch), a deliberate loss round on desktop retried with the R key, then a mid-match resize (desktop to 700 px, phone to 844x390 landscape). It records console/page errors, frame times (rAF intervals), time-to-ready and rematch latency. Reports: `qa/before-report.json`, `qa/after-report.json`. The jac dev server full-reloads on any write inside the repo, so the script captures to `/tmp` and copies at the end.

## Bugs found and fixed

| Bug | Root cause | Fix |
|---|---|---|
| Every reload logs `POST /user/register 400` in the console | `_join` always called `jacSignup` before `jacLogin`, re-registering the account already saved in `sessionStorage` | Returning tabs log in first; sign up only for new or rejected credentials (`client/battlefield.jac`) |
| Phone in landscape cannot see the field while aiming (field 770x385 starting at y=175 in a 390 px viewport) | Field width was always 100% of the column with a 2:1 aspect, and the masthead/briefing kept desktop spacing | Short-landscape media query compacts the header and caps the field width at `(100dvh - 96px) * 2` |
| Win/loss is almost invisible: only a small HUD word changes, the launcher still says STAND BY | No end-of-duel presentation; launcher label had only two states | Field result banner, DUEL OVER / BOT AIMING launcher states, Rematch button highlights when ready |
| Shell parks on its last sample until the reveal closes, so impacts read as the ball stopping | Playback held the final path sample with no landing event | Landing is detected when playback passes the last server timestamp; the shell is replaced by an impact (dataset playback fields unchanged) |
| Phone portrait: header buttons stack in a narrow column and push the field down; "Practice bot" wraps | `.utilities` capped at 144 px | Utilities move to their own row on narrow portrait screens |

## Polish and feel (all cosmetic, reduced-motion aware)

- Goal within 5 s: a YOUR TURN banner states the objective for the phase (flare first, then shell the remembered core), and a ghost pull eases back from the launcher with a DRAG BACK cue until the first drag or arrow key.
- Aiming: guide dots became triangle chevrons rotated to the launch angle (atan2 heading) with a travelling sine pulse; a live `power% angle°` readout; a breathing ring and orbiting chevrons mark the launcher on your turn; the field frame glows on your turn.
- Shots: comet tail oriented by atan2 of successive samples, fading trail, launch recoil ring and muzzle shards.
- Impacts: triangle shards (trig burst, gravity and drag), flash rings, modest camera shake (150 ms at 0.005 for shells, 260 ms at 0.009 when your core falls). Flares get a soft rising glow and no shake.
- End of duel: VICTORY / OUTPOST LOST / DRAW banner with back-eased pop and rotating triangle crests, triangle confetti on a win, burst on the destroyed core.
- Retry: press R (or the highlighted Rematch) when a duel ends; rematch reached your turn again in about 0.2 s locally.
- Replay reason: local record chip (wins-losses, streak, best streak) in `localStorage`, counted once per room:epoch so reloads do not double count.
- Fog: four blurred wisps drift on sine paths over the hidden half (mirrored for seat B), under the authorized reveal drawing.
- With `prefers-reduced-motion`: no shake, confetti, orbit or drift; fewer and slower shards; banners appear without scaling.

New pure helpers in `client/presentation.js` (`trianglePoints`, `headingOf`, easing, `burst`/`stepShards`, `bannerFor`, `recordAfter`/`recordLabel`) are covered by `tests/feel_client.test.mjs` (6 tests), added to `scripts/verify.sh`.

## Verification

- `bash scripts/verify.sh`: Jac 65 passed, Node 22 passed (16 existing + 6 new), shot race, two seats, presentation interactions and practice lifecycle all ok. Exit 0.
- `bash scripts/verify-sealed.sh`: build, bundle guard, sealed shot race, two seats, practice lifecycle and `sealed app smoke ok`. Exit 0.
- `jac check client/battlefield.jac`: exit 0, same warning classes as main.
- Playtest after: zero console errors and zero page errors at both sizes, including reload. Frame time while idle and during flight was about 16.5 ms avg with p95 16.8 ms at both sizes (software WebGL). The before run's first desktop idle sample was 29.6 ms avg, which is probably warm-up noise, so it is not claimed as an improvement.

## Not changed / remaining ideas

- The match is deterministic: the same flare and the same lob `(10, 390)` win every practice duel in three turns. Escalation needs server-side layout variety (a seeded outpost per rematch, or a bot that gets better as your streak grows). That touches authority, physics fixtures and many tests, so it is out of scope here.
- No audio assets exist; no sound was added.
- Real phones, screen readers and long sessions were not tested; this is headless Chromium only.
