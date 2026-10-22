# Changelog

All notable changes to Fogshot are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-21

First versioned release. Fogshot is playable from source or a local sealed
package. Hosting is not set up yet (see [BUILD-STATUS](docs/BUILD-STATUS.md)).

### Added
- Jac-first game foundation: Jac 0.37.23 serves a Phaser 3.90.0 field. Shots
  follow an authoritative Pymunk 7.3.0 path, braced supports break, supply
  edges are walked, and illegal pulls are rejected. Coordinates that haven't
  been revealed stay on the server.
- Two-seat matches backed by a journal. A restarted match is restored, repeated
  commands are ignored, and a refreshed browser can reclaim its seat. Supply
  lamps, a playable broken supply, core-loss endings and a rematch control.
- Private rooms with a room code (`?room=`) instead of a shared password. Quiet
  seats are released after 30 s, and two simultaneous shots produce one flare
  and one `busy` response
  ([#1](https://github.com/CosmonautJones/fogshot/pull/1)).
- Moonlit look: original terrain, launch machinery and material art, bounded
  observation and projectile effects, a responsive HUD and keyboard controls
  ([#8](https://github.com/CosmonautJones/fogshot/pull/8)).
- Solo **Practice** against a fair, deterministic bot. It only uses what its own
  scouting revealed. Its turns survive a reload, and rooms are published
  atomically ([#9](https://github.com/CosmonautJones/fogshot/pull/9)).
- A clean-checkout `scripts/verify.sh` (behavior suite, client playback and a
  two-browser check) and a CI check that builds the sealed package and smokes it
  ([#1](https://github.com/CosmonautJones/fogshot/pull/1),
  [#8](https://github.com/CosmonautJones/fogshot/pull/8)).

### Fixed
- The sealed Jac 0.37.23 package now keeps its executable main entry
  ([#8](https://github.com/CosmonautJones/fogshot/pull/8)).
- Delayed observations expire before playback and HUD updates, and B's physical
  pull mapping, cancelled or multiple touches, and switching between keyboard
  and pointer all work ([#8](https://github.com/CosmonautJones/fogshot/pull/8)).
- First-play launch guidance stays visible below the battlefield, stale aiming
  text clears, and garbled characters in the HUD placeholders are gone
  ([#10](https://github.com/CosmonautJones/fogshot/pull/10)).

[Unreleased]: https://github.com/CosmonautJones/fogshot/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/CosmonautJones/fogshot/releases/tag/v0.1.0
