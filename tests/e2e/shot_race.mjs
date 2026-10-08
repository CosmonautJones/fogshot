// Two authenticated shots at the protected HTTP boundary, sent together.
// One may simulate. The other must be a rejection or the stored receipt.
const api = process.env.FOGSHOT_API || "http://127.0.0.1:8001";

function fail(message) {
    console.error(message);
    process.exitCode = 1;
}

async function register(email, password) {
    const res = await fetch(`${api}/user/register`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
            credential: { type: "password", password },
            identities: [{ type: "email", value: email }],
        }),
    });
    const body = await res.json();
    if (!body.data || !body.data.token) {
        throw new Error(`register failed ${res.status} ${JSON.stringify(body).slice(0, 300)}`);
    }
    return body.data.token;
}

async function call(token, name, args) {
    const res = await fetch(`${api}/function/${name}`, {
        method: "POST",
        headers: {
            "content-type": "application/json",
            authorization: `Bearer ${token}`,
        },
        body: JSON.stringify(args),
    });
    const body = await res.json();
    const raw = body && body.data ? body.data.result : "";
    const parsed = typeof raw === "string" ? JSON.parse(raw) : raw;
    return { status: res.status, parsed };
}

const stamp = Date.now();
const tokenA = await register(`race-a-${stamp}@example.com`, `pw-a-${stamp}-isolated`);
const tokenB = await register(`race-b-${stamp}@example.com`, `pw-b-${stamp}-isolated`);
const denied = await call(tokenA, "join_seat", { invite: "fogshot" });
if (denied.parsed.ok || denied.parsed.code !== "unauthenticated") {
    fail(`the shared invite was accepted: ${JSON.stringify(denied.parsed)}`);
}
const created = await call(tokenA, "create_room", {});
const quieted = await call(tokenB, "create_room", {});
const room = created.parsed.room || "";
const quiet = quieted.parsed.room || "";
if (!/^[0-9a-f]{6}$/.test(room) || !/^[0-9a-f]{6}$/.test(quiet) || room === quiet) {
    fail(`rooms were not isolated: ${JSON.stringify({ created: created.parsed, quieted: quieted.parsed })}`);
}
const joinedA = await call(tokenA, "join_seat", { invite: room });
const joinedB = await call(tokenB, "join_seat", { invite: room });
const parked = await call(tokenA, "join_seat", { invite: quiet });
if (joinedA.parsed.seat !== "A" || joinedB.parsed.seat !== "B" || parked.parsed.seat !== "A" || parked.parsed.room !== quiet) {
    fail(`seats were not free: ${JSON.stringify({ a: joinedA.parsed, b: joinedB.parsed, parked: parked.parsed })}`);
} else {
    const shot = (commandId) => call(tokenA, "loose_shot", {
        invite: room,
        command_id: commandId,
        epoch: 1,
        expected_turn: 0,
        expected_revision: 0,
        weapon: "flare",
        pointer_x: 20,
        pointer_y: 300,
        canvas_w: 800,
        canvas_h: 400,
        dpr: 1,
    });
    const [first, second] = await Promise.all([
        shot(`race-${stamp}-1`),
        shot(`race-${stamp}-2`),
    ]);
    const rows = [first.parsed, second.parsed];
    const accepted = rows.filter((row) => row.ok && row.weapon === "flare" && !row.code);
    const settled = rows.filter((row) => row.code === "turn" || row.code === "busy" || row.code === "revision" || (row.ok && row.code === ""));
    const watched = await call(tokenB, "watch_match", { invite: room, now_ms: 0 });
    const untouched = await call(tokenA, "watch_match", { invite: quiet, now_ms: 0 });
    console.log(JSON.stringify({
        codes: rows.map((row) => ({ ok: row.ok, code: row.code || "", weapon: row.weapon, turn: row.turn, phase: row.phase })),
        watch: { phase: watched.parsed.phase, turn: watched.parsed.turn, seat: watched.parsed.seat, room: watched.parsed.room },
        quiet: { phase: untouched.parsed.phase, turn: untouched.parsed.turn, seat: untouched.parsed.seat, room: untouched.parsed.room },
    }));
    if (untouched.parsed.room !== quiet || untouched.parsed.turn !== 0 || untouched.parsed.phase !== "recon") {
        fail(`the quiet room moved: ${JSON.stringify(untouched.parsed)}`);
    }
    if (accepted.length !== 1 || watched.parsed.phase !== "recon" || watched.parsed.turn !== 1 || watched.parsed.room !== room) {
        fail(`both shots simulated or neither did: accepted ${accepted.length}, phase ${watched.parsed.phase}, turn ${watched.parsed.turn}`);
    }
    if (settled.length !== 2) {
        fail(`a shot response was not a receipt or a stable rejection: ${JSON.stringify(rows.map((row) => row.code))}`);
    }
}

if (process.exitCode) {
    process.exit(process.exitCode);
}
console.log("shot race ok");
