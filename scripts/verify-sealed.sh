#!/usr/bin/env bash
# Exercise the distributable, after scripts/verify.sh has stopped its source server.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
jac build
python3 tests/sealed_bundle_test.py dist/fogshot.jab

port="${FOGSHOT_SEALED_PORT:-8180}"
url="http://127.0.0.1:${port}"
if curl -fsS -o /dev/null --max-time 2 "$url/"; then
    echo "sealed smoke port is already in use: $port" >&2
    exit 1
fi
JAC_SERVE_HOST=127.0.0.1 JAC_SERVE_WORKERS=1 JAC_SERVE_THREADS=2 jac run --port "$port" dist/fogshot.jab >.jac/verify-sealed.log 2>&1 &
started="$!"
cleanup() {
    local status="$?"
    trap - EXIT INT TERM
    kill "$started" >/dev/null 2>&1 || true
    for _ in {1..100}; do
        if ! kill -0 "$started" 2>/dev/null; then
            break
        fi
        sleep 0.1
    done
    if kill -0 "$started" 2>/dev/null; then
        kill -KILL "$started" >/dev/null 2>&1 || true
    fi
    wait "$started" 2>/dev/null || true
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
ready=""
for _ in {1..60}; do
    if ! kill -0 "$started" 2>/dev/null; then
        cat .jac/verify-sealed.log >&2
        exit 1
    fi
    if curl -fsS -o /dev/null --max-time 2 "$url/"; then
        ready="yes"
        break
    fi
    sleep 1
done
if [[ -z "$ready" ]]; then
    cat .jac/verify-sealed.log >&2
    echo "sealed app did not become ready" >&2
    exit 1
fi
FOGSHOT_API="$url" node tests/e2e/shot_race.mjs
FOGSHOT_URL="$url/" FOGSHOT_PLAYWRIGHT="${FOGSHOT_PLAYWRIGHT:-${root}/.jac/e2e/node_modules/playwright}" node tests/e2e/two_seats.mjs
FOGSHOT_URL="$url/" FOGSHOT_API="$url" FOGSHOT_PLAYWRIGHT="${FOGSHOT_PLAYWRIGHT:-${root}/.jac/e2e/node_modules/playwright}" node tests/e2e/practice.mjs
echo "sealed app smoke ok"
