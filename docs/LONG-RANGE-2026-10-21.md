# Long-range artillery - 2026-10-21

Branch `feature/long-range`, stacked on `feature/procedural-duels` (PR #12). Merge after #11 and #12.

Playtest feedback was that the launch felt like a short slingshot toss ("like Angry Birds"). Generated ridges
now play as long-range artillery in the Scorched Earth / Worms / Gunbound mould: a wide field with real
terrain in between, a power-and-angle launcher that can throw well past the enemy, and a camera that
follows the shell out and back. Ridge 0 (the classic fixture) and any stored pre-branch layout keep the old
short game, so the existing browser suites still cover it.

## Scale, before vs after

| | Before (classic / PR #12 ridges) | After (generated long ridges) |
| --- | --- | --- |
| Field | 40 x 16 m | 124-160 m wide (varies per ridge) x 96 m sky |
| Launcher gap | 28 m (6 / 34) | 100-148 m |
| Launcher to enemy core | 3.5-6.6 m downrange of own launcher, ~22-25 m attack | 82-124 m (+-2 m), drawn evenly per seat |
| Shot speed | cap 22 m/s, ~7 m/s practical | up to 44 m/s |
| Full-pull range (45 deg, light drag) | ~10 m | ~178 m - well past the far edge |
| Typical flight | under 1 s | 3-7 s (played back at 1.6x) |
| Terrain | 0-1.5 m bumps | layered sines, a central hill (5-11 m) or twin hills with a valley, side hills; up to 14 m |

Shells burst on first contact (blast radius 1.5 m, falloff), so a core breaks when the burst lands within about
0.9 m of it. Each outpost sits 12-58 m in front of its own launcher, inside its own half.

## Aiming

- **Drag anywhere** (relative): pull back and down from any point on the field, like a slingshot; the drag vector
  sets angle and power (a full 240 px pull is 44 m/s). A drag starts from the current locked aim, so a second
  drag nudges the last aim rather than replacing it. Releasing **locks** the aim; it does not fire. The locked aim
  stays for your next turn so corrections start from the last shot.
- **Fine tune** with the aim bar under the field (phones and desktop): `angle -/+` (0.5 deg), `power -/+` (0.5%),
  or the keyboard: Up/Down angle, Left/Right power, Shift x4, Escape clears, H goes home.
- **FIRE** (button, Enter or Space) sends the shot. The readout shows angle and power %.
- **Partial preview arc**: only the first 0.4 s of flight is drawn (with chevrons), so you see the launch direction
  but the preview never solves the shot. Range marks every 20 m along the ground help read distance.
- Server protocol is unchanged in spirit: the client sends a pad pointer; the server re-derives angle and power
  (`release_long`) and enforces the same angle rule and the higher power cap.

## Camera

- **Home**: your launcher at 20% (seat A) or 80% (seat B) of the view.
- **Follow**: during any flight (yours or incoming) the camera tracks the shell, then holds 1.4 s on the burst
  (`impact`), then eases back home.
- **Look**: the overview minimap strip at the top of the field shows the whole ridge, your view box, launchers and
  the shell. Tap or drag on it to look anywhere; off-turn drags on the field pan the camera; the aim bar has
  look-back / Home / look-ahead buttons.
- `data-camera`, `data-camera-x/y` on `#fogshot-field` expose the state for tests.

## Fairness and fog

- Fog of war is unchanged in kind: the enemy half is fogged, the outpost is hidden, and each shot opens a local
  reveal patch (flare 6 m, powered shell 4.5 m, shell 3.5 m) for the flight plus 3.5 s. A shell that leaves the
  field reveals nothing and its path is trimmed at the edge. The shooter sees its whole arc; the defender only sees
  the part over their own half.
- The generator keeps the classic contract, retuned: swept angle/power exposure 5-30% for each seat (measured
  median ~18%), seats within 12 points, real Pymunk proof shots for both seats, settle drift <= 0.12, and the old
  scripted flare + lob (with and without the flare first) must not break a core. A screen also rejects any core
  hit by the popular pulls or by flat full-power shots (10-30 deg), the easiest family to memorise.
- **Popularity**: no pad pull on a 20 px grid hits more than 25% of generated ridges for either seat (tested over
  40 ridges). Drawing the field first piled most cores up 80-90 m away, and one remembered pull hit ~30% of
  ridges; drawing the attack distances evenly first and fitting the field around them brought the worst pull on a
  10 px grid to 7/36 (19%) per seat.
- About 10% of ridges find no fair layout in 40 attempts and hand over to the deterministic fallback ridge (same as
  PR #12); generation takes 0.3-9 s per ridge (~11 s when it falls back), hidden by the layout pool.

## Practice bot

Long ridges use `_choose_long`: it solves public ballistics (free flight over the public ground, no hidden pieces)
for a target, trying angles 45, 40, 50, 35, 55, 60, 30, 65, 25 until one clears the hills. Known targets come from
revealed bodies it remembers; blind shots scout the public core band (12-58 m in front of your launcher, inside
your half, 80-124 m from it). Error is in power fraction and degrees and shrinks with your practice win streak and
with each shell it has fired: `(max(0.002, 0.03 r), max(0.1, 1.6 r))`, `r = 0.7^streak * 0.75^shells`.

## Wind

Considered and deferred. Wind is fun in Worms/Gunbound because it is shown and changes every turn; here it would
also have to be part of the generator's fairness proof (exposure and popular-pull screens per wind state) and of
the bot's public solver. That doubles generation time, which is already up to ~9 s per ridge. Better as its own
slice once generation is faster.

## Known issues

- Terrain does not deform (no craters).
- A shell that leaves the field plays out to the edge with nothing revealed; there is no "off the map" banner.
- About 10% of ridges use a fallback ridge; worst-case generation ~11 s (pooled).
- Very long flights on phones: the minimap strip is small (26-47 px); tap targets are fine but the shell dot is tiny.
- Pymunk and the analytic validator agree for the proof shots, but tiny numeric differences mean a swept-window
  edge shot can differ between the screen and the live world.
