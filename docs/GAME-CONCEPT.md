# FOGSHOT
## Multiplayer blind-aim physics siege — concept specification v0.1

**Status:** Proposed design for review, not an approved implementation plan or a validated game.
**Date:** October 4, 2026
**Working title:** Fogshot. Name availability has not been checked.

> You do not aim at what you can see. You aim at what you remember.

## 1. The brief

The player's original concept is a multiplayer combination of Battleship-style hidden opponents and Angry Birds-style pull-back launching and physical destruction. Players freely aim into unseen enemy territory, damage buildings and supply lines, and win by wiping out their opponent's infrastructure. Spatial memory, awareness, and learning from previous shots should matter more than luck. The visual direction is clean, animated, expressive, and physically satisfying.

This proposal adds the following assumptions for a testable first version: 1v1, a fixed 2D side-view arena, alternating turns, short local reveals, four objective buildings per player, and browser delivery as a distribution goal. Platform, numbers, title, and additional mechanics are proposals rather than requirements supplied by the player.

**Experience target:** Players form a hypothesis about an unseen target, make a deliberate launch adjustment, and receive enough feedback to improve their next hypothesis. A miss can still be informative. A successful attack can also change the layout they thought they understood.

**Not a claim:** This design has not demonstrated demand, retention, competitive balance, cognitive benefits, or originality across the entire games market.

## 2. The distinguishing loop

Place and protect infrastructure → scout a small area → remember its relationships → pull back and launch blind → watch a local collapse → infer what changed → choose the next target.

The proposed distinction is not simply artillery plus destructible buildings. It is an evolving mental map of a destructible, partially observed enemy network. Players should say, “The depot was below the ledge, but that support just fell. A flatter shot should reach it now.”

The most important tension is between information and damage. A flare sacrifices immediate damage to improve the next attack. A destructive shot may expose useful infrastructure but also move or bury it.

## 3. Format and alternatives

### Recommended: fixed side-view duel

Two compact industrial outposts face one another across a valley. Public terrain and distant landmarks remain visible. Each player can always inspect their own outpost. Enemy infrastructure is hidden by a consistent visual fog mask except during authorized reveals.

The aiming camera returns to the same scale, orientation, and reference position each turn. Cinematic motion is presentation only and must not change launch coordinates or hide essential information.

### Alternatives considered

- **Top-down or angled 2.5D:** More independent horizontal targeting directions, but projectile height, collisions, and collapse relationships need more explanation. Worth testing only after the basic loop works.
- **Full 3D:** Offers spectacle, but depth judgments and changing camera views could overwhelm the intended memory-and-launch interaction. Not recommended for the first version.

The initial game should not include real-time base management or free camera rotation.

## 4. Match structure

### Preparation

Each player starts with the same four objective modules and the same construction budget. Place modules within a compact legal build region, choose protective prefabs, and connect useful modules to the launch station. Presets provide an immediate ready-to-play option.

For the first playable slice, use a small collection of validated layouts and bounded placement slots. A full freeform construction editor is not required to test the concept.

A proposed 60-second preparation clock is a starting value, not a proven requirement. Ready players can advance early when both have confirmed.

Both sides must use equally reachable build regions. Placement validation rejects objectives outside bounds, invulnerably embedded in terrain, or beyond the legal launch envelope. Protected is allowed; unreachable is not.

### Opening reconnaissance

Before damaging attacks begin, each player receives one free non-damaging flare launch. It uses the same pull-back controls as every other shot. It reveals a local patch, never the complete enemy layout. Its purpose is to provide an initial aiming reference and something meaningful to remember.

Both players finish this reconnaissance phase before the first damaging turn.

### Attack turns

On a turn, a player receives the applicable supply recharge, chooses a projectile, aims, and releases one shot. After launch, the authoritative simulation resolves flight, impacts, structural failure, and bounded settling. Revealed regions are shown according to the visibility rules. The next turn starts after resolution, not during it.

Proposed starting values: 20 seconds to choose and aim, roughly 2–5 seconds for ordinary resolution, and a target match length of 8–12 minutes. These are design targets to measure and tune, not predictions of actual play.

No mandatory wait is added when a player fires early. Timing out consumes the turn without inventing an automatic shot.

### Victory

Destroy all four enemy objective cores. Decorative debris, disconnected roads, and the launch station are not victory targets.

An objective remains alive when disconnected or displaced. It is destroyed when its core reaches zero health, including damage caused by impacts and crushing, or when the core leaves the legal playable world. A collapsed outer building is not automatically a destroyed core; this must be visually legible.

The server checks victory after the resolving shot and its bounded damage sequence settle. If that sequence eliminates both sides, the result is a draw. Disconnection or surrender can produce a forfeit under separate match rules.

The launcher is an indestructible utility platform outside the build zone. It does not count as an objective. Losing infrastructure must not prevent a player with a surviving objective from using a basic shot.

Starting-player advantage is an open balance question. Randomize the opener and record the effect during testing; mirrored terrain alone is not proof of fairness.

## 5. The information contract

**Principle:** Blind at the moment of choosing an attack, but never deprived of all useful feedback.

### Always visible

- The player's own infrastructure, health, links, and supplies.
- Public terrain, arena boundaries, fixed landmarks, and launch locations.
- The total number of surviving enemy objectives, without automatic coordinates.
- The player's own launch gesture and limited initial trajectory guide.

### Hidden by default

- Enemy building positions, remaining health, supply balances, link topology, and unrevealed collapse state.
- Enemy defenses and rubble outside currently revealed regions.
- Any complete trajectory prediction or landing reticle into enemy territory.

### Ordinary shot reveals

A shot travels into the obscured area. Its first impact opens a small world-anchored visibility window around the impact, whether it hit an objective, rubble, or empty ground. Within that patch, the player can watch the immediate destruction and see nearby clues. The patch then closes.

Initial tuning values: a visible footprint approximately one building-width across and a 3–4 second review window. The review countdown should not be consumed by network loading. Exact dimensions and timing must be playtested.

A secondary explosion outside the authorized patch does not automatically reveal the entire enemy base. It can produce only the coarse feedback explicitly allowed by the game rules.

### Flare reveals

A flare produces no damage and reveals a larger local patch for a short, fixed review period. It reveals the current state, not a guaranteed future target location. The normal reveal size and duration are public weapon properties.

An attached recon tower can increase the footprint as specified in the infrastructure rules. It must not grant a permanent live view.

### Feedback and memory aids

Material cues distinguish dirt, metal, wood, explosions, and major collapses. Essential information also has equivalent icon or caption feedback; headphones and hearing acuity must not be prerequisites.

Allow up to three manually placed, approximate memory pins. Pins represent player guesses, carry a last-edited turn label, and never attach to or follow hidden objects. Do not automatically preserve exact enemy silhouettes after fog returns.

A previous-pull indicator can help players adjust their launch without supplying a full future trajectory. Test its effect on learning rather than assuming it improves play.

All authorized reveals are potential screenshot material. The game must remain interesting through changing physical state and interpretation; it cannot rely on preventing players from remembering or recording information they legitimately saw.

### Endgame search

If cleanup becomes tedious, test a symmetric limited-sector reconnaissance sweep beginning after full round 10 and recurring every three rounds. Its sectors rotate on a public schedule independent of actual survivor locations. It is temporary, does not aim weapons, and does not change the all-objectives-destroyed victory condition.

This is an optional tuning rule to test, not a feature required in the first prototype.

## 6. Launching and physics

Drag backward from the launcher to set direction and pull strength. Release to launch. Mouse and touch use the same world-space mapping, with keyboard/controller adjustment as an accessibility route. A canceled drag does not fire.

The launch vector is continuous within a bounded playable angle and power range. It is not a grid selection. A short trajectory segment is allowed near the launcher; a full solution through fog is not.

Start with fixed gravity and no wind, random accuracy spread, random critical hits, or random midair drift. Under unchanged starting conditions, equal launch inputs should have predictable flight. Later environmental modifiers must be visible and stable long enough for players to learn them.

Use structural pieces with simple collision shapes and breakable connections. Three initial materials are sufficient: light wood, heavier masonry, and resilient metal. Their exact health, mass, and break thresholds are balance data.

Explosions apply a bounded impulse and damage. Support failure can create falling pieces, secondary collisions, and crushing damage. Surviving rubble remains meaningful cover or an obstacle. Cosmetic dust and fragments do not all require gameplay physics.

Define an upper simulation budget for settling. Projectile cleanup, sleeping bodies, and a documented settle cutoff prevent an indefinitely rolling object from holding the turn open. Any forced finalization must be consistent and visible, not a secret reroll of the shot.

Destruction should be readable before it is realistic: a broken support, a lean, a fall, a crunch. Avoid making a building vanish as an undifferentiated health bar.

## 7. Infrastructure and supply network

The first proposed outpost contains four objective buildings. Each offers a modest perk while a functioning supply path connects it to the launcher. There is no universal power dependency in this version; a single lost power plant does not switch off every other building.

| Objective | Perk while connected | Effect of losing its connection |
|---|---|---|
| Power plant | One bonus supply charge every third own turn | Normal baseline recharge remains |
| Supply depot | Supply storage cap increases from 4 to 6 | No further refill above the normal cap |
| Workshop | Breacher costs 2 charges instead of 3 | Breacher remains available at its normal cost |
| Recon tower | Flare footprint radius increases by 25% | Baseline flare remains available |

**Baseline supply economy:** Start combat with 2 charges after the free opening recon phase. Gain 1 charge at the beginning of every subsequent own turn, subject to the active cap. Basic shots cost zero. No more than one projectile is fired per turn. The first combat turn does not also add an extra starting recharge.

For counting the power bonus, combat turns are numbered from 1; the bonus is awarded at the start of own turns 3, 6, 9, and so on if the plant is connected then. This avoids ambiguous timing on the first turn.

If the depot disconnects while the player holds more than the new cap, already-held charges are preserved. Recharge pauses until balance is below the applicable cap. Resources are not confiscated invisibly.

All numerical values in this section are a consistent starting ruleset, not validated balance.

### Physical links, not a spreadsheet economy

Supply links are visible roads, pipes, or bridge sections that can be hit and severed. In the rules they form a graph: buildings and junctions are nodes; intact segments are edges. After shot resolution, recompute which objectives have a valid path to the launch station. A surviving alternate path preserves the perk.

The visual appearance and graph state must agree. Detached rubble does not conduct supplies. A hovering road cannot silently connect endpoints that have moved apart.

Construction budget limits both protection and link length. Compact bases spend less on routing but risk multi-building blast damage. Spaced bases reduce that risk but need longer or more exposed connections.

Do not simulate individual cargo inventories or dozens of trucks in the first version. Animated deliveries can communicate connectivity without becoming separate gameplay systems.

Repairs and rerouting are expansion candidates. They are excluded from the initial ruleset so the first build does not require mid-match construction or introduce indefinite repair loops.

## 8. Weapons

| Weapon | Initial cost | Role | Limitation |
|---|---:|---|---|
| Standard shell | 0 | Learn range, break ordinary protection, finish objectives | Moderate localized damage |
| Scout flare | 1 | Reveal a larger region to improve a later attack | No damage; consumes the attack turn |
| Breacher | 3, or 2 with connected workshop | Break a remembered support or armored point | Narrow useful area; inaccurate shots waste charges |
| Scatter shot — later | 3 proposed | Search an uncertain area with several weak impacts | Poor penetration; spread pattern must be explicit and repeatable |
| Disruptor — later | 2 proposed | Temporarily disable a local supply route | Little or no core damage; temporary benefit |

Only the first three weapons belong in the first playable slice. All use the same pull-back launch interaction.

Avoid homing weapons, permanent full-map reveals, opponent-targeted automatic strikes, and unbounded area damage that erases the need to learn where anything is. Future weapons should change the player's decision, not replace their aim.

## 9. Visual and audio direction

The proposed setting is a stylized miniature industrial siege: toy-like machinery, expressive outposts, compact cranes and conveyors, chunky structural materials, and fictional crews. Avoid copying recognizable characters, interface layouts, or branded assets from the reference games.

Use clean silhouettes, controlled color, restrained textures, and strong separation between foreground targets and decorative background. Teal/slate fog and warm machinery accents are one possible palette, not a locked visual requirement.

Buildings can react before destruction: a generator shudders, a tower lists sideways, a warning lamp flickers, crates slide from a platform. A local collapse should have anticipation, impact, and a short readable aftermath.

Audio completes the hidden space: creaking support, an uncertain clank, then a much larger crash. These are rule-defined cues, not unrestricted audio access to hidden object positions.

Provide reduced camera shake, reduced motion, readable contrast, non-color-only ownership indicators, and equivalent feedback for important sound cues. Essential shot information must not depend on a fleeting cinematic camera angle.

## 10. Example of intended play

The opening flare catches the edge of an enemy workshop above a narrow supply bridge. The player remembers the workshop relative to a public cliff notch, but does not see the rest of the outpost.

A standard shot lands short. Its reveal shows the bridge's left support and some empty ground. The player now has a range reference rather than merely a failure message.

On the next turn, a stronger, lower shot breaks the support. The local patch shows the bridge tipping and the workshop sliding partly behind rubble. Its connection is lost, increasing the opponent's future Breacher cost, but the opponent can still fire.

The player must now choose between another scan, a precision Breacher toward the remembered workshop, or searching elsewhere. Repeating the identical shot is not necessarily correct because the physical target has changed.

That inference-and-adjustment sequence is the experience the prototype must demonstrate.

## 11. Multiplayer architecture boundary

Browser delivery is a proposed way to make friend invitations easy. Engine choice should follow a small physics and deployment test, not precede evidence that the interaction works. This specification does not select an untested framework or guarantee an export target.

For a fair online match, use a trusted server as the authority for private layouts, accepted launch commands, resource spending, physics outcomes, turn order, and victory. Clients should submit a bounded weapon/angle/power command, not a claimed hit or result.

Resolve the authoritative shot once. Send each player only the state, animation events, and reveal patches that player is allowed to observe. Do not ship the whole enemy map to a browser and assume a fog overlay makes it secret. Filter snapshots, events, audio, spectator views, and reconnection payloads consistently.

Clients may animate or interpolate permitted results. They do not decide hidden collisions. A fixed timestep is useful, but is not a promise that unrelated devices will independently produce identical rigid-body outcomes. Store authoritative snapshots and permitted event streams rather than relying on seed-only replays before determinism has been verified.

Maintain a shot identifier and turn number so duplicate or late commands cannot spend resources twice or launch extra attacks. Validate finite numeric inputs, angle/power bounds, weapon cost, active player, and match state.

On reconnect, restore the latest settled authoritative state filtered to that player's permissions. No private layout should leak through a convenience full-state synchronization. Spectators either receive a player-limited view or a sufficiently delayed omniscient replay, not a live channel for scouting opponents.

Proposed initial disconnect policy: pause once per player at a settled boundary for a short reconnect grace period; then forfeit if they do not return. Grace duration and abuse handling are tuning/configuration decisions, not reasons to freeze an active projectile indefinitely.

## 12. Prototype sequence and scope

### Gate A: shot feel

One local arena, visible targets, the pull-back gesture, standard projectile, three materials, and a readable collapse. No network, economy, or construction editor is needed to answer whether firing feels good.

### Gate B: blind-memory loop

Add fog, opening recon, local impact reveals, a small hidden layout, and objective counting. Use repeatable test scenarios and player observation. Confirm that players can explain their next adjustment and do not experience every shot as a guess.

### Gate C: multiplayer vertical slice

Two players join a private room. One arena, validated layout options, four objective buildings per side, three weapons, alternating turns, the simple supply graph, a reliable end condition, and immediate rematch. Apply the server/visibility boundary from the outset of online play.

The supply perks can be disabled in test variants to establish whether they add understandable decisions beyond simply hitting buildings.

**Excluded initially:** Campaign, 2v2, free-for-all, procedural world generation, full freeform base construction, mid-match repair, mobile store releases, ranked matchmaking, a large weapon catalog, live operations, voice chat, progression grind, and monetization.

## 13. Questions the playtest must answer

1. Can a newcomer launch deliberately after a minimal tutorial?
2. Does the second or third shot show an informed correction, rather than unexplained variation?
3. Are reveal duration and radius enough to understand damage without making the enemy permanently visible?
4. Do players target supports and supply links intentionally?
5. Can a player losing infrastructure still make meaningful attacks?
6. Is finding the final objective exciting or tedious?
7. Do opponents want an immediate rematch without being prompted?

Suggested early test targets, explicitly unvalidated: most first-time testers can describe why a shot missed after a few attempts; most can state the purpose of a flare; median match duration lands near the intended range; and a substantial share voluntarily choose rematch. Small initial samples are directional learning, not statistical proof.

Instrument launch inputs, turn duration, reveal use, objective damage, link disconnections, first-player outcomes, final-objective cleanup time, disconnects, and rematch choices. Pair the data with players explaining what they believed was behind the fog.

## 14. Principal risks and mitigations

| Risk | Design response to test |
|---|---|
| Blind attacks feel random | Predictable flight, useful local miss feedback, opening reconnaissance, limited trajectory guide |
| Destruction is hidden and unsatisfying | Impact-centered visibility window long enough to read a local collapse |
| Memory becomes exhausting | Stable landmarks/camera, approximate manual pins, compact arenas |
| Repeating a successful aim solves everything | Changing rubble/support geometry, multiple separated objectives, information/damage tradeoff |
| A supply hit snowballs into helplessness | Free basic shot, guaranteed baseline recharge, perks rather than hard weapon locks |
| Full construction produces inaccessible targets | Validated layouts first; strict placement and reachability bounds later |
| Repairs prevent matches from ending | No repair system in the initial version |
| Final cleanup drags | Public remaining-objective count; test symmetric temporary sector scans |
| Hidden data is exposed by clients | Server-owned private state and per-player filtered updates |
| Physics outcomes disagree | Authoritative simulation and stored outcomes; no unverified cross-device lockstep assumption |

## 15. Related games and limits of the comparison

EarthWork Games describes **Forts** as a physics-based real-time strategy game involving custom bases, resources, weapons, and structural destruction. Its development notes also document fog of war. This is a relevant neighboring design, not a feature set to ignore.

The official **ShellShock Live** site describes multiplayer tank battles, varied weapons, and fully destructible terrain. It is another useful point of comparison for trajectory combat and changing battlefields.

The proposal here emphasizes brief local information, blind pull-back attacks, evolving spatial memory, and supply infrastructure within a compact turn-based duel. A limited comparison with these games does not establish market-wide uniqueness.

Sources consulted October 4, 2026:
- EarthWork Games, Forts official site: https://www.earthworkgames.com/
- EarthWork Games, Tim's Forts Work Log: https://www.earthworkgames.com/tims-forts-work-log/
- kChamp Games, ShellShock Live official site: https://www.shellshocklive.com/

## 16. Recommendation

Build toward the smallest proof of the loop: a player remembers a support behind the fog, deliberately adjusts a pull, and watches the structure collapse where they expected. Prove that this is satisfying before adding an elaborate economy, a large arsenal, or multiple modes.

The center of this game is not hidden targets alone. It is a hidden world that changes when you hit it.
