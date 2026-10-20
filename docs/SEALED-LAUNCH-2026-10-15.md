# Sealed launch follow-through — 2026-10-15

Jac 0.37.23 now launches Fogshot's sealed web app locally. The correction is an empty server boot block in `main.jac`; no game rules, solver, projection, endpoint or placement pins changed.

## Failure classification

The supported command is `jac run dist/fogshot.jab`. The previous polished artifact (SHA-256 `d5250d92ea0679401a691db9000dac01edd04d737affe4862ea2124767563803`) reproduced the missing executable `main.jac` error. Its original artifact and log were preserved before changes.

A detached, untouched base commit `81bb802433a9049b23c80af8e82433aff6e4b953` was independently built with identical installed pinned dependencies. Its 3,075,243-byte artifact (SHA-256 `5a12f625a8bd16ca1ffdb750a16d2d54663e7435f10deede313694367f6bb33e`) failed identically. This is a pre-existing packaging incompatibility, not a visual-polish regression or wrong launch command.

The bundled pinned compiler deliberately omits client-only modules during sealing. Fogshot's JSX-only entry was classified client-only, so its manifest declared `main.jac` as the entry but contained no corresponding executable. The sealed loader requires that executable. An empty `with entry {}` produces a harmless server-side pass, retaining the entry without moving the battlefield onto the server.

## Regression and actual artifact checks

- Before correction, `python3 tests/sealed_bundle_test.py <preserved-artifact>` failed with `sealed entry has no executable module: main.jac`.
- `jac check main.jac client/battlefield.jac`: passed (existing interop/JSX/explicit-any warnings).
- `jac build`: passed, 12/12 executable modules, with only `client/battlefield.jac` skipped as client-only.
- The corrected artifact passed the declared-entry presence and executable SHA-256 guard.
- Actual `jac run --port 8180 dist/fogshot.jab`: loaded sealed artifacts, initialized, and returned HTTP 200. No source/dev server was running on that port.
- 14 Node tests passed. Real authenticated shot race passed against the sealed app/API.
- The first existing two-seat smoke stalled at the first combat gesture. That failing log was retained. A diagnostic run with gesture coordinates and accepted-receipt summaries passed both seats' wins, rematches, supply changes, reveal expiry and existing privacy assertions. The test now focuses before measuring the field and awaits each actual HTTP command receipt, failing immediately on rejection rather than proceeding from polling alone. Its corrected run passed the full flow; no retries, response stubs or gameplay changes were used.
- Independent code review found a smoke-process cleanup gap. The runner now waits for its owned PID, preserves the original test status, handles interrupts, and bounds shutdown. Final review cleared it.
- The local artifact server ran as one process on loopback and exited successfully after TERM; port closure was checked.

The local smoke artifact was 3,746,327 bytes, SHA-256 `b89236ee5c33c29701d763327631bf1354854ea664fbe48e2868a55c847cfd35`. This artifact predates this evidence document and test-runner-only edits; the actual game boot correction was present. Final-head CI rebuilds and exercises the complete committed package.

## Reproduce

Use the repository's pinned Jac 0.37.23 and installed dependencies:

```sh
bash scripts/verify.sh
bash scripts/verify-sealed.sh
```

The second command builds the artifact, checks its declared executable entry, serves it on an unused port (default 8180), and runs actual shot-race and two-seat browser checks. It uses the Playwright installation from the first command. `FOGSHOT_PLAYWRIGHT` and `FOGSHOT_BROWSER_CHANNEL` can select an existing compatible installation.

For a manual sealed launch:

```sh
JAC_SERVE_HOST=127.0.0.1 JAC_SERVE_WORKERS=1 JAC_SERVE_THREADS=2 \
  jac run --port 8180 dist/fogshot.jab
```

In production mode the app and API share that port. Pinned JAB dispatch forwards `--port` but drops `--host` and `--workers`; the supported environment settings above retain the intended loopback binding and single worker. `--api-port` only applies in dev mode.

CI now runs the sealed smoke after the existing full behavior/client/browser verification. Current run status belongs to the PR checks; a successful build alone does not qualify launch. No merge, hosting deployment, physical-device qualification or production-ready claim is made.
