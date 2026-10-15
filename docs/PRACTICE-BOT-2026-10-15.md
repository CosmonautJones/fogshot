# Practice bot — 2026-10-15

Practice is being implemented on a separate branch based on reviewed visual/packaging head `70d289babbb9353f4bb906cbc6d135c02de6655a`. PR #8 and its port 8180 playtest remain frozen.

The backend checkpoint adds a deterministic seat B policy that accepts only a copied normal seat observation and its own bounded remembered points. It never receives a LiveMatch, physics world, canonical bodies, health, hidden seed or owner identity. It scouts with the normal flare, remembers coarse positions actually exposed by its legal reveal, then chooses imperfect legal pulls using public free-flight estimates. No model calls or new dependencies.

Practice rooms reserve human A and bot B for one authenticated owner. Creating practice again reuses that owner's private room. Owner-only polling drives a bot turn after the human reveal deadline plus a short pause; closing the page pauses advancement. Planning and shots use per-room locks and a stable epoch/turn/revision command id. Plans, memory and due times are stored in the same atomic canonical snapshot as gameplay. Shot failure restores them; rematch resets them and persists its new epoch.

Backend checkpoint: all 63 Jac behavior tests passed, including the original 50, five pure-policy tests and eight practice lifecycle/concurrency tests. Tests cover hidden-state metamorphism, expired observation memory, bounded memory, valid pulls, owner isolation, restart, duplicate and simultaneous polling, failed writes, both win outcomes and rematch. The original red missing-feature tests and intermediate failures are retained outside the repository. UI/sealed/browser integration and independent final review are still in progress at this checkpoint.

The browser companion gauge uses the reachable gesture envelope as its display scale; server power, submitted coordinates and physics stay unchanged. Its separate client regression passed before UI integration. Final playable evidence will be recorded here after actual browser and sealed-package verification.

No merge, deployment, spending or production-readiness claim.
