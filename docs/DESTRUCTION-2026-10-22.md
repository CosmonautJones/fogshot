# Destruction: craters and breakable structures - 2026-10-22

Branch `feature/destruction`, stacked on `feature/long-range` (PR #14). Merge after #11, #12 and #14.
Classic mode (ridge 0 and stored pre-branch layouts) is unchanged; everything below is armed only on
generated long-range ridges (`arm_long(world, layout)`).

## Approach and sources

We did not invent a destruction engine. Both halves are textbook 2D-artillery patterns, built on
what Pymunk already ships:

| Piece | Pattern | Source |
| --- | --- | --- |
| Destructible ground | Worms / Scorched Earth style **bitmap terrain**: an authoritative grid, carved by circular blasts, re-traced into collision geometry | Pymunk's own example [`examples/deformable.py`](https://github.com/viblo/pymunk/blob/master/pymunk/examples/deformable.py) (`march_soft` + `simplify_curves` into static `Segment`s); [`pymunk.autogeometry`](http://www.pymunk.org/en/latest/_modules/pymunk/autogeometry.html); viblo's answer on [deforming terrain in Pymunk](https://stackoverflow.com/questions/70043954) (use segments, not polys, since polys must be convex) |
| Rebuild cost | Only the dirty **chunks** are re-marched; untouched chunks keep their original segments | Same deformable example (it re-marches tiles around the edit) |
| Breakable blocks | Break a body past a damage / **impulse threshold** from the post-solve callback, then swap in pre-made fragments | Box2D testbed [`breakable.cpp`](https://github.com/erincatto/box2d/blob/v2.4.1/testbed/tests/breakable.cpp) (`PostSolve` max normal impulse, break later outside the step); Chipmunk2D [`demo/Slice.c`](https://github.com/slembcke/Chipmunk2D/blob/master/demo/Slice.c) (split a shape into two convex bodies that keep the parent's velocity, done in a post-step) |

Why a density grid and not polygon clipping (pyclipper / Shapely): neither is installed in the
sealed runtime, the grid is pure Python + Pymunk (already a dependency), it is trivially
deterministic, and Pymunk's marching-squares is designed for exactly this.

## Ground (physics/pymunk_driver.jac, `TerrainMask`)

- Signed density grid, 0.25 m cells, built lazily per column from the public ridge:
  `density = 0.5 + (ground(x) - y) / cell`. A crater applies `min(density, 0.5 + (dist - r) / cell)`
  (signed-distance CSG), so the iso-line at 0.5 is the exact ridge where nothing was carved.
- Field is cut into 4 m chunks. A carve returns the dirty chunks; each is re-traced with
  `autogeometry.march_soft` (threshold 0.5) and `simplify_curves` (0.02 m), then swapped in as static
  `Segment`s (radius 0.08 m). Contours meet the untouched neighbour's segments exactly at chunk edges.
- Untouched chunks keep the original 1 m polyline segments, so a field with no craters is
  bit-for-bit the pre-destruction world (generator, proofs and the classic suites are unaffected).
- Crater radius 1.4 m (blast radius is 1.5 m). Only shells carve; flares never do.
- **Bedrock** at y = -5 m is never carved. **Launcher pads are indestructible**: columns within
  2.5 m of either launcher are never carved (a clear rule: you can always fire).
- After a carve, sleeping bodies within reach are woken (`body.activate()`), so anything resting on the
  removed ground falls into the crater. Sleeping (`sleep_time_threshold = 0.5 s`) is on for
  destructible worlds so settled rubble costs nothing.
- Crater marks are rounded to 1e-4 before they are applied, so `rewind_craters(marks)` on a fresh world
  reproduces the identical segments (reload and rollback use it).

## Structures

| Body | Destructible? | Rule |
| --- | --- | --- |
| Timber blocks | yes | health 0.7; one solid burst breaks them into **3** fragments |
| Stone blocks | yes | health 2.4; takes about two to three bursts, breaks into **4** fragments |
| Fragments (`debris`) | yes | timber 0.25 / stone 0.7 health; a later burst pulverises them |
| Cores | yes (unchanged) | static, health 0.4; break on a burst or a crush from a falling piece |
| Braced masts (posts) | yes (unchanged) | pin breaks, the mast topples and can crush |
| Footing, plinth, spur fixtures | no | static scenery, as before |
| Ground | yes | craters, except bedrock and launcher pads |

- **Pre-scored fracture**: the block's rectangle is split along its long side at 38-62%, repeatedly
  (largest piece first), using an LCG seeded by `crc32(block id)`: same block, same pieces, every run.
- Fragments take their place in the parent and the parent's velocity **at that point**
  (`velocity_at_world_point`), plus a small outward (0.6 m/s) and upward (0.4 m/s) kick.
- The burst that broke a block does not also pulverise its fresh fragments. It still pushes them, but a
  fragment's kick is capped at 4 m/s. Without the cap, a 0.03 kg piece of roof left the field at 37 m/s.
- Rubble landing on the ground or on other rubble does no damage; a fragment only hurts a real block
  (e.g. a core) with an impulse of at least 0.15, so a pebble cannot snipe a core but a falling stone can.
- **Cap**: at most 24 live fragments; the oldest are removed first.

## Server and privacy (server/live.jac)

- Craters are stored with the seat that fired them (`crater_seats`) and saved in `canonical.json`
  with the debris specs. Reload re-carves and re-creates fragments before restoring body states.
  A failed shot transaction rewinds the craters with the bodies.
- Watch payloads gain `craters: [[x, y, r], ...]`, filtered per seat: a seat sees its **own** shells'
  craters and **any** crater on its own half. A shell that lands short on the shooter's own side never
  reaches the defender. Rows carry only position and radius - no shooter, no seed, no pad rule.
- Fragments are `SecretBody` entries owned by the seat that owned the parent block (`debris-timber` /
  `debris-stone`), so `project_view` shows enemy fragments only inside a live reveal patch, clipped
  like every other hidden body. Hidden layout cannot leak through debris.
- The ground the client draws is the public ridge plus the craters it was sent. Launcher pads: the
  client only knows its own pad and skips only that one; an attacker's crater drawn near the hidden enemy
  pad is not clamped (doing so would reveal the pad).

## Client (client/presentation.js, client/mount_field.js)

- `carveTerrain(terrain, craters, pads)` (pure, node-tested) lowers every column a crater covers to
  the circle's lower arc; `craterRims` gives the bowl for a scorched rim with thrown-up clods.
- Ground, crest, range marks, the launcher foot, camera look targets and the minimap strip all use
  the carved profile. Shell bursts on long fields throw brown dirt clods.
- A new crater is held back while its shell is still flying in the playback and appears on landing,
  so the server's early answer never spoils the flight (`dataset.cratersShown` vs `dataset.craters`).
- Fragments draw in their parent's material tone with a crack line.
- `dataset.craters`, `dataset.debris`, `dataset.fps` (from `game.loop.actualFps`) for tests and QA.

## Performance

| Measure | Result |
| --- | --- |
| Carve + re-trace dirty chunks (24 random carves, 100 m ridge) | mean 1.5 ms, worst 2.1 ms |
| Full proof shot on a generated ridge (fire to settle, ~1,300 steps, fracture + carve) | ~7 ms server CPU, 3 fragments, 12 bodies |
| Client frame rate (`game.loop.actualFps`, headless Chromium, through blasts and debris) | desktop 1280x800: min 59 / median 60; mobile 390x844: min 57 / median 60 |
| Layout generation (40 ridges, now with carving and fracture in proofs) | mean 2.6 s, 0.2-8.3 s (was 0.3-9 s) |

Budgets enforced by tests: mean carve < 40 ms, worst < 120 ms, one proof shot < 2.5 s, fragments <= 24.

## Fairness and anti-script checks

Re-run with destruction live in every proof and scripted-break check: all `layout_tests` pass. The
grid-pull popularity measure is unchanged at **7 / 36 ridges (19%)** per seat (bar is 25%), exposure
0.085-0.273, 4 of 40 ridges use the deterministic fallback.

## Tests

`tests/destruction_tests.jac` (11): deterministic carving that only touches nearby chunks and rewinds
exactly; pads cannot be cratered; a resting (sleeping) block and a later shell fall into a fresh crater;
fracture only past threshold and stone outlasts timber; fragments inherit velocity; fracture is
deterministic; debris cap and gentle-contact immunity; craters and debris survive a reload, flares never
carve, and each seat only receives the craters it may see; carve and shot cost bounds; a proof shell's
fragments reach the enemy only inside the reveal patch (ids outside it never appear in the payload);
a burst throws fragments a few metres, not off the field.
`tests/destruction_client.test.mjs` (5): carving profile, overlap, pads, garbage rows, debris sizing.

## Playtest

`qa/destruction-playtest.mjs` at 1280x800 and 390x844 (touch): ground before a blast, the burst with dirt
clods, the crater after, the bot's shell on our half, a proof shell on the enemy outpost (fragments in
the reveal patch) and the overview. Mid-flight check: the server had already sent the new crater
(`craters` = 1) while the client still showed 0 until the shell landed. The playtest pins public ridges
49183 (desktop) and 27055 (mobile), whose proof shell fractures the enemy roof on the local dev server.
It hit both: VICTORY with fragments in the reveal patch, 0 console errors and no overflow. Contact sheet `qa/destruction.png`, captures in `qa/destruction/`.

## Known issues / not done

- Craters are surface bowls: the client draws a heightfield, so a rare cave under an overhang is drawn
  as an open bowl (the server collision is still exact).
- Fragments are axis-aligned rectangles (pre-scored), not Voronoi shards.
- The practice bot aims at the public ridge; it does not plan around craters.
- Generation time is unchanged in range but still up to ~8 s on unlucky ridges (pooled ahead of time).
