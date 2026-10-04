# ADR 0001: Jac-first, server-authoritative Fogshot

Date: 2026-10-04
Status: Selected architectural direction; integration compatibility is not yet verified.

## Decision

Build a browser-first 2D duel with authored gameplay and client orchestration in Jac. Use Phaser for presentation and evaluate Pymunk as a server-side physics primitive library controlled from Jac. Target JacHammer after verifying its actual runtime, dependencies, storage, and process topology.

The server owns enemy layouts, accepted shots, collision outcomes, damage, structural breaks, turn order, and victory. The client submits bounded angle, power, weapon, command ID, and expected revision/turn. It never submits a claimed hit.

Only allowlisted per-player views and replay observations leave the server. Do not send an entire private world and cover it with fog. Apply the same boundary to initial state, poll responses, captions, errors, replay, and reconnect. Do not expose a layout seed or template selection that reconstructs the private world.

Persist settled checkpoints and resolved events. Use a fixed simulation step, bounded body count, and bounded settling. Do not assume independent clients reproduce identical physics or that a process-local lock supports multiple server workers.

Supply segments map to Jac graph edges. A physical break updates logical connectivity; alternate intact paths preserve it. Basic shots never require connectivity, and a disconnected objective does not count as destroyed.

## Jac ownership

Jac: input mapping, scene lifecycle, application state, rules, damage policy, structural-failure policy, visibility, sessions/matches, persistence orchestration, and graph traversal.

Dependencies: Phaser rendering/input primitives; Pymunk rigid bodies/shapes/contacts/constraints. A small JavaScript interop adapter requires a demonstrated problem and rationale. No separate handwritten Python gameplay service by default. No LLM calls for game authority or physics.

## Consequences

The integration must be proved before expanding scope. Native Jac/WebAssembly can be evaluated for a measured hot path later; building a general-purpose game engine is not a prerequisite. A static mock, scripted collapse, or browser-owned hidden world is not acceptable evidence of the intended architecture.

The first playable is deliberately narrower than the parent concept: one objective per side, opening flares and free shells, and a supply indicator. The full weapons/economy and base construction remain future work.
