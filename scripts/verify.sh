#!/usr/bin/env bash
# Clean-checkout check for the pinned Jac toolchain.
# Jac 0.37.23: curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jaseci/main/scripts/install.sh | bash -s -- --version 0.37.23
# Then: jac install && scripts/verify.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
export PATH="${HOME}/.local/bin:${PATH}"

version="$(jac --version)"
echo "$version"
case "$version" in
    *"0.37.23"*) ;;
    *)
        echo "expected jac 0.37.23" >&2
        exit 1
        ;;
esac

export JAC_TEST_STRICT=1
jac test \
    tests/physics_driver_tests.jac \
    tests/scene_host_tests.jac \
    tests/aim_rules_tests.jac \
    tests/siege_view_tests.jac \
    tests/authority_tests.jac \
    tests/supply_tests.jac \
    tests/live_match_tests.jac \
    tests/outcome_tests.jac \
    tests/qa_match_tests.jac \
    tests/clock_authority_tests.jac \
    tests/command_envelope_tests.jac \
    tests/transaction_tests.jac \
    tests/impact_reveal_tests.jac \
    tests/playback_tests.jac \
    tests/outpost_tests.jac \
    tests/b_win_tests.jac \
    -v

node --test tests/playback_client.test.mjs

playwright_dir="${root}/.jac/e2e"
if ! NODE_PATH="${playwright_dir}/node_modules" node -e "require.resolve('playwright')" >/dev/null 2>&1; then
    mkdir -p "$playwright_dir"
    npm install --prefix "$playwright_dir" playwright@1.55.1
fi
if [[ -z "${FOGSHOT_BROWSER_CHANNEL:-}" ]]; then
    NODE_PATH="${playwright_dir}/node_modules" npx --prefix "$playwright_dir" playwright install chromium
fi

started=""
if ! curl -fsS -o /dev/null --max-time 2 http://127.0.0.1:8000/; then
    jac run >"${root}/.jac/verify-server.log" 2>&1 &
    started="$!"
    trap 'kill "$started" >/dev/null 2>&1 || true' EXIT
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
        if curl -fsS -o /dev/null --max-time 2 http://127.0.0.1:8000/; then
            break
        fi
        sleep 2
    done
    curl -fsS -o /dev/null --max-time 2 http://127.0.0.1:8000/
fi

FOGSHOT_PLAYWRIGHT="${playwright_dir}/node_modules/playwright" node tests/e2e/two_seats.mjs
