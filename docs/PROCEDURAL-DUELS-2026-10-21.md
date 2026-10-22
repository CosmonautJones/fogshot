# Procedural duels - 2026-10-21

Branch `feature/procedural-duels`, stacked on `polish/playtest-pass` (PR #11). Merge after #11.

Every duel, and every rematch, is now played on a newly generated ridge. The server
generates, validates and keeps the layout. Clients get only the public parts: the
ridge number and name, the ground profile and their own launcher.

## What varies per duel

| Element | Range | Public? |
| --- | --- | --- |
| Ground profile | Three layered sines plus a cosine bowl or hump at the midline. Mirrored, 0-1.5 m. | yes |
| Launcher position | x 4.8-7.2 m, 3.2-5.6 m above a flattened pad. Mirrored. | yes |
| Core | Size 0.6-0.9 m. 3.5-6.6 m downrange, sometimes raised on a plinth. | no |
| Footing | 1.9-3.2 m wide, keyed to the ground under it. | no |
| Cover | Optional roof. 1-3 walls or crates, some stacked. Timber (light, fragile) or stone (heavy, tough). | no |
| Supply mast | Height 1.8-3.2 m, lean ±0.08-0.24 rad, placed elsewhere in the zone. | no |
| Spur | An optional decoy rock. | no |

Moving the launcher changes what every canvas pull does, so pulls cannot be memorised
from one ridge to the next.

## Seeds and privacy

- **Public ridge number.** A public ridge number (1-99999) names the duel. The HUD shows it as, for example, `FOLD #48213`.
- **Private seeds.** The private seeds are `sha256(server_secret:ridge:stream)`. The secret comes from `FOGSHOT_LAYOUT_SECRET` or from `ROOM_ROOT/.layout-secret`, which is created on first use. Neither the open-source generator nor the public number can rebuild the hidden outposts offline.
- **Shared links.** `?ridge=N` replays ridge N on the same server (new room or practice). `?ridge=0` is the classic hand-tuned layout, kept as the regression fixture for the browser suites. An explicit ridge can only replace a finished or untouched duel. The Rematch button never sends one: it always rolls a fresh ridge.
- **Fallback.** If a ridge has no fair layout, a deterministic fallback ridge is used. About 10% of ridges need one.
- **Structures are not mirrored.** A mirrored copy of your own (visible) outpost would reveal the enemy's. Each side is generated independently, and the two sides are balanced by a measured exposure instead.
- **Where layouts live.** Layouts are stored with the room: in `canonical.json` and `layout.json`, server-side only. A small in-memory pool of fresh layouts hides generation latency. None of this is sent to clients.

## Validation

Every layout must pass all of the following checks (`game/layout.jac`):

- **Geometry.** Pieces are in bounds and on their own side, at least 2.4 m clear of the launchers, with no overlapping boxes, masts not buried, and all required roles present.
- **Stability.** In a 240-step Pymunk settle, no block or mast moves more than 0.12.
- **Reachability and fairness.** An analytic free-flight sweep of every legal pull on a 0.35 m grid measures the share of pulls whose first contact is the enemy core. Each side must be between 1.2% and 9%, and the two sides within 2.5 points of each other. So a core is always findable but never trivially exposed, and both sides face comparable odds.
- **Proof.** A real Pymunk shell from a swept direct-hit pull breaks each core.
- **Anti-script.** The old classic lob (10,390) and its neighbours, plus the two most popular direct-hit pulls, may not reach the core first. A full Pymunk run of the lob pulls must leave both cores standing. Across 50 ridges, no single canvas pull on a 20 px grid is a direct hit on more than 25% of them.

## Practice bot ramp

`choose(observation, memory, skill)` is deterministic for its inputs. The server supplies
a private per-room bot seed and the player's practice win streak.

- **Aim error.** Seeded Gaussian error with `sigma = max(1, 26 * 0.7^streak * 0.75^shells_this_duel)` canvas px. Measured first-shell hit rate on a core the bot has already seen: about 15% at streak 0, 46% at streak 2 and 77% at streak 4. It is wide for a new player, tightens as they keep winning, and tightens as the bot zeroes in during a duel. A loss resets the streak.
- **Scouting and aim.** Blind pulls wander from a seeded pattern. The opening flare keeps its pattern. Aim is computed from the bot's own launcher, read from its legal observation.
- **Level display.** Practice HUD shows `BOT LV n` (n = streak + 1).

## Client

- Public ground drawn as a filled crest with strata lines.
- Three seeded sine-ridgelines with small triangular crags behind it.
- Launcher towers reaching the ground.
- Material detail for timber (grain and X-brace), stone (coursed masonry) and footing/spur (triangle rubble). Shattered blocks vanish.
- Pull feedback is launcher-aware.

## Tests

- **`tests/layout_tests.jac`:**
  - determinism per ridge and secret
  - 50 distinct layouts
  - validity, stability, reachability and balance for all 50
  - anti-script and popularity
  - live wins for both seats on generated ridges
  - privacy of the payload
  - rematch rolls a new ridge, and replay and classic pinning work
  - bot seed and streak ramp
- **`tests/ridge_client.test.mjs`:** launcher-aware pull feedback, seeded ridgelines, terrain polygon and labels.
- **Browser suites:** they pin `?ridge=0` where they script exact classic pulls. They also check that Rematch rolls a generated ridge.

## Playtest

`qa/proc-playtest.mjs` covers:

- six shared ridges at 1280x800 (the contact sheet is `qa/proc-layouts.png`);
- practice rematch chains at 1280x800 (mouse) and 390x844 (touch).

Each duel opens with the old scripted flare (20,300) + lob (10,390). Results are in `qa/proc-report.json`.

### Results

Run on the dev server, 2026-10-21:

- **Scripted flare+lob:** won 0 of 10 duels (10 distinct ridges).
- **Outcomes:** human 4, bot 5, unfinished 1. The scripted "human" only fires the fixed script and follow-up list, so these numbers say nothing about the balance of a real player.
- **Console:** 0 errors and 0 page errors. The only warnings are headless Chromium's software-WebGL notices.
- **Layout:** no horizontal overflow at 390x844.
- **Generation:** about 0.3-12 s per ridge on the box (median about 1.5 s). Fresh ridges come from a background pool, so a room or rematch usually does not wait.
- **Before the anti-script guard:** the lob won 4 of 8 playtest duels, and 15 of 20 ridges in a headless sweep. The same sweep found the most popular single pull hit 41% of ridges.

## Known limits

- **Fallback ridges.** About 10% of ridge numbers have no fair layout under a given server secret. They hand over to a deterministic fallback, so a shared link can show a different number than it asked for.
- **Anti-script coverage.** The guard covers the human's scripted flare followed by the lob. A bot flare that happens to nudge cover first is not simulated. The popularity bound (25%) is checked with free flight on a 20 px grid, not with a full Pymunk run.
- **Scoutless practice duels.** If neither side reveals the other's core, a practice duel can go on for a long time. The playtest had one such duel unfinished after 32 shells. The bot's error narrows each shell, but its blind search is still a seeded wander.
- **Pool is per process.** The ridge pool lives in memory per server process. Multi-worker hosting would just generate more.
