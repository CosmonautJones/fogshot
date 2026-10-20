# FOGSHOT

> You do not aim at what you can see. You aim at what you remember.

A Jac-first multiplayer physics-siege game: pull back, launch into a hidden outpost, remember the brief glimpse, and bring its infrastructure down.

**Current status: Jac 0.37.23 serves the Phaser 3.90.0 field. Two isolated seats share a private room, pull-back shots follow the authoritative Pymunk path, impacts reveal temporary patches, broken supports update supply, and both seats can win and rematch. Original moonlit art, a responsive HUD and keyboard controls are implemented. Source/dev play and local sealed-package launch are verified; hosting remains unqualified.** See [BUILD-STATUS](docs/BUILD-STATUS.md) and [RUNTIME](docs/RUNTIME.md).

## Selected direction

Jac owns authored game rules, scene orchestration, input conversion, structural-damage policy, turn authority, visibility projection, and the supply graph. Phaser 3.90.0 is the pinned browser presentation dependency. Pymunk 7.3.0 is the trusted low-level 2D solver, called from Jac through a `::py::` import seam. JacHammer is the intended initial hosting target, not a completed deployment.

This is not a JavaScript game with a cosmetic Jac endpoint. It is also not a claim that the third-party renderer or solver was written in Jac.

## First playable

Two independent browser sessions. One launcher and one supported objective per side. A free opening scout shot for each player, then alternating shell attacks. Local impact reveals, physically falling debris, a connected-supply indicator, and a reliable victory/draw result. The full four-objective, three-weapon economy comes afterward.

## Documents

- [Game concept](docs/GAME-CONCEPT.md)
- [Architecture decision](docs/adr/0001-jac-first-authoritative-game.md)
- [First-playable implementation plan](docs/FIRST-PLAYABLE.md)
- [Build status and evidence](docs/BUILD-STATUS.md)
- [Jac 0.37.23 evidence for later agents](docs/JAC-0.37-EVIDENCE.md)
- [Agent working agreement](AGENTS.md)

## Development

Do not guess a Jac scaffold or toolchain version. Start with the runtime gate in the implementation plan, pin compatible releases, and document the exact verified commands before presenting installation instructions as working.

Commit and push small, coherent changes frequently. Preserve hidden-state privacy, do not publish credentials or user data, and never claim a deployment or test result without evidence.

A distribution license has not yet been selected. Original presentation artwork and provenance are documented in [assets/README.md](assets/README.md); no reference-game assets are included. See the [visual polish report and evidence](docs/VISUAL-POLISH-2026-10-14.md).
