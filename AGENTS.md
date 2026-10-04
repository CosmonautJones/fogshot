# Fogshot working agreement

## Product boundary

Read README.md, docs/GAME-CONCEPT.md, docs/adr/0001-jac-first-authoritative-game.md, docs/FIRST-PLAYABLE.md, and docs/BUILD-STATUS.md before changing the game.

Build in Jac, not a TypeScript implementation with a token Jac route. Use the actual installed Jac documentation and pin the working toolchain. Keep the third-party renderer and solver clearly identified. Do not invent language syntax and call it verified.

## Commit and push frequently

The owner explicitly requested a PUBLIC Fogshot repository and frequent commits and pushes.

Commit after each coherent, verified slice. Push that commit to the authorized remote branch promptly when an authenticated remote is available. Avoid a large unpushed batch. Each meaningful commit should explain the behavior it changes. A failed push must be reported with the local SHA and exact blocker; local commits are not remote progress.

Use a feature branch for gameplay work after the initial repository bootstrap. Never force-push, rewrite published history, delete branches, widen permissions, publish a package, incur paid hosting, or alter unrelated repositories without separate authorization. The request to publish Fogshot does not authorize publishing unrelated files or credentials.

## Evidence and tests

Write a behavior test first, observe it fail for the intended reason, implement the smallest change, and rerun the relevant suite. Record the exact commands and results in docs/BUILD-STATUS.md or a linked build-evidence record. Do not label missing dependencies, skipped suites, static screenshots, or mock responses as passing gameplay evidence.

Before each commit: inspect the diff; run git diff --check; inspect tracked paths for secrets and private data; run the relevant available checks. Bootstrap documentation has no gameplay test suite and must say so.

Test two isolated sessions, duplicate commands, wrong actor/turn/revision, crash/restart recovery, thin-support collisions, bounded settling, and hidden-data projection. Private data must not leak through replay, errors, source maps, reconnect, seeds, captions, or debugging endpoints.

## Public repository safety

Commit only original Fogshot source, configuration, tests, and relevant design/evidence. Do not copy personal conversation records, proprietary employer code, third-party game assets, authentication files, environment files, private match databases, or captured seat tokens. Redact private data in logs and screenshots before publication.

## Session continuity

Update docs/BUILD-STATUS.md at each completed slice or real blocker. State what runs, what was tested, exact local/remote commit status, and the next concrete task. No implied background work. Keep product development in the dedicated Fogshot workspace.
