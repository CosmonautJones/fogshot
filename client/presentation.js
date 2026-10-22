// Presentation math only. Authority, clipping and trajectory samples stay on the server.
export function bodySize(body) {
    return { width: Math.max(0, body.w * 20), height: Math.max(0, body.h * 25) };
}

// `launcher` is the seat's public launcher in world metres (generated ridges move it).
export function pullFeedback(seat, pointer, launcher) {
    const lx = launcher && Number.isFinite(launcher.x) ? launcher.x : seat === "B" ? 34 : 6;
    const ly = launcher && Number.isFinite(launcher.y) ? launcher.y : 4;
    const origin = { x: lx * 20, y: (1 - ly / 16) * 400 };
    const wx = pointer.x / 20;
    const dx = lx - wx;
    const dy = ly - (1 - pointer.y / 400) * 16;
    const rawPower = Math.hypot(dx, dy);
    const angle = Math.atan2(dy, dx);
    const power = Math.min(22, rawPower);
    const valid = Number.isFinite(power) && rawPower >= 1 && Math.cos(angle) * (seat === "B" ? -1 : 1) > 0.25 && Math.sin(angle) > -0.35;
    const guide = [];
    // A short direction cue, not a landing or collision prediction.
    if (valid) {
        for (let n = 1; n <= 7; n++) {
            const distance = n * 6;
            const x = origin.x + Math.cos(angle) * distance;
            const y = origin.y - Math.sin(angle) * distance;
            if ((seat === "B" && x <= 400) || (seat !== "B" && x >= 400)) break;
            guide.push({ x, y });
        }
    }
    return { valid, power, angle, guide, origin, pullFraction: Math.min(1, rawPower / Math.hypot(6,4)) };
}

export function hudState(data) {
    const result = data.result || "";
    const draw = result.toLowerCase() === "draw";
    return {
        turn: result ? (draw ? "Draw" : result === data.seat ? "Victory" : "Outpost lost") : data.your_turn ? "Your turn" : data.seat ? data.mode === "practice" ? "Practice bot aiming" : "Opponent aiming" : "Connecting…",
        weapon: data.phase === "recon" ? "Scout flare" : "Standard shell",
        supply: data.own_powered === false ? "Supply cut · shell available" : "Supply connected",
        enemy: data.enemy_cores === undefined ? "—" : String(data.enemy_cores),
        core: data.own_core === false ? "Lost" : "Standing",
    };
}

// The server protocol mirrors B input; gestures themselves stay in screen space.
export function protocolPull(seat, pointer) {
    return { x: seat === "B" ? 800 - pointer.x : pointer.x, y: pointer.y };
}

// Normalize delayed observations before either playback or HUD bookkeeping.
export function observationAt(data, now) {
    if (!data.view || !data.view.reveal || Number(data.reveal_until) > now) return data;
    // These legacy fields describe B's post (server.live._encode). Its owner
    // may retain them; another viewer may not retain an expired observation.
    const ownPost = data.seat === "B";
    return {
        ...data, view: { ...data.view, reveal: null },
        reveal_until: 0, reveal_x: 0, reveal_y: 0, reveal_radius: 0,
        path: [], collapse: [], collapse_id: "",
        broken: ownPost ? data.broken : false,
        angle: ownPost ? data.angle : 0,
    };
}

// ---- Game-feel helpers (pure; presentation only, never authority) ----

// Corners of an isosceles triangle centred on (x, y), nose pointing along `angle`
// (screen radians, y down). Used for particles, guide chevrons and the shell nose.
export function trianglePoints(x, y, size, angle) {
    const nose = { x: x + Math.cos(angle) * size, y: y + Math.sin(angle) * size };
    const spread = 2.5; // rear corners sit ~143 degrees either side of the nose
    return [
        nose,
        { x: x + Math.cos(angle + spread) * size * .7, y: y + Math.sin(angle + spread) * size * .7 },
        { x: x + Math.cos(angle - spread) * size * .7, y: y + Math.sin(angle - spread) * size * .7 },
    ];
}

// Screen heading between two points via atan2; null when the step is too small to trust.
export function headingOf(from, to, minStep = .5) {
    if (!from || !to) return null;
    const dx = to.x - from.x, dy = to.y - from.y;
    if (Math.hypot(dx, dy) < minStep) return null;
    return Math.atan2(dy, dx);
}

export function easeOutBack(t) {
    const c = 1.70158, u = Math.min(1, Math.max(0, t)) - 1;
    return 1 + (c + 1) * u * u * u + c * u * u;
}

export function easeOutCubic(t) {
    const u = 1 - Math.min(1, Math.max(0, t));
    return 1 - u * u * u;
}

// Deterministic radial burst of triangle shards. `rand` is injectable for tests.
export function burst(x, y, { count = 14, speed = 120, spread = Math.PI * 2, heading = -Math.PI / 2, life = .7, size = 4, rand = Math.random } = {}) {
    const shards = [];
    for (let i = 0; i < count; i++) {
        const a = heading - spread / 2 + spread * ((i + rand() * .8) / count);
        const v = speed * (.45 + rand() * .75);
        shards.push({ x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v, rot: a, spin: (rand() - .5) * 14, age: 0, life: life * (.6 + rand() * .6), size: size * (.6 + rand() * .8) });
    }
    return shards;
}

// Advance shards with gravity and drag; drops expired ones.
export function stepShards(shards, dt, gravity = 260) {
    const out = [];
    for (const s of shards) {
        const age = s.age + dt;
        if (age >= s.life) continue;
        const drag = Math.max(0, 1 - 1.6 * dt);
        out.push({ ...s, age, x: s.x + s.vx * dt, y: s.y + s.vy * dt, vx: s.vx * drag, vy: s.vy * drag + gravity * dt, rot: s.rot + s.spin * dt });
    }
    return out;
}

// What the field banner should say for a given match payload.
export function bannerFor(data) {
    if (!data || !data.seat) return null;
    const result = data.result || "";
    if (result) {
        if (result.toLowerCase() === "draw") return { kind: "draw", title: "DRAW", sub: "Both outposts went dark. Press R or Rematch." };
        if (result === data.seat) return { kind: "victory", title: "VICTORY", sub: "Enemy core destroyed. Press R or Rematch." };
        return { kind: "defeat", title: "OUTPOST LOST", sub: "Your core fell. Press R or Rematch." };
    }
    if (data.your_turn) {
        return data.phase === "recon"
            ? { kind: "turn", title: "YOUR TURN", sub: "Fire a flare into the fog. Remember what it shows." }
            : { kind: "turn", title: "YOUR TURN", sub: "Shell the core you remember." };
    }
    return null;
}

// Local win/loss record so there is a reason to queue another duel.
// `key` identifies one finished duel (room:epoch) so reloads never double count.
export function recordAfter(record, data, key) {
    const base = { wins: 0, losses: 0, draws: 0, streak: 0, best: 0, counted: [], ...(record || {}) };
    const result = (data && data.result) || "";
    if (!result || !data.seat || base.counted.includes(key)) return base;
    const next = { ...base, counted: [...base.counted, key].slice(-40) };
    if (result.toLowerCase() === "draw") { next.draws += 1; next.streak = 0; }
    else if (result === data.seat) { next.wins += 1; next.streak += 1; next.best = Math.max(next.best, next.streak); }
    else { next.losses += 1; next.streak = 0; }
    return next;
}

export function recordLabel(record) {
    if (!record || (!record.wins && !record.losses && !record.draws)) return "RECORD 0-0";
    const draws = record.draws ? `-${record.draws}` : "";
    const streak = record.streak > 1 ? ` · STREAK ${record.streak}` : "";
    return `RECORD ${record.wins}-${record.losses}${draws}${streak} · BEST ${record.best}`;
}

// ---- Procedural ridge art (presentation only; terrain is public, structures never are) ----

// Small seeded PRNG for cosmetic variety keyed by the public ridge number.
export function ridgeRandom(seed) {
    let state = (Math.abs(Math.floor(seed)) * 2654435761 + 1013904223) >>> 0 || 1;
    return () => {
        state ^= state << 13; state >>>= 0;
        state ^= state >>> 17;
        state ^= state << 5; state >>>= 0;
        return state / 4294967296;
    };
}

// Distant silhouettes: each layer sums a few sines with seeded wavelengths and phases.
// Returns screen polylines (800 x 400), back layer first.
export function ridgeLines(ridge, layers = 3, step = 16, width = 800) {
    if (!ridge || ridge <= 0) return [];
    const rand = ridgeRandom(ridge);
    const out = [];
    for (let layer = 0; layer < layers; layer++) {
        const base = 228 + layer * 30 + rand() * 14;
        const waves = [0, 1, 2].map(k => ({ amp: (16 - layer * 3) / (k + 1) * (.6 + rand() * .8), freq: (k + 1) * (.006 + rand() * .01), phase: rand() * Math.PI * 2 }));
        const points = [];
        for (let x = 0; x <= width; x += step) {
            let y = base;
            for (const w of waves) y -= w.amp * Math.sin(x * w.freq + w.phase);
            // A sharp triangular peak now and then, like a far relay crag.
            y -= Math.max(0, 1 - Math.abs(((x * .004 + layer * .37 + waves[0].phase) % 1) - .5) * 9) * (10 - layer * 2);
            points.push({ x, y: Math.round(y * 10) / 10 });
        }
        out.push(points);
    }
    return out;
}

// Public ground profile (world metres) to a closed screen polygon down to the bottom edge.
export function terrainPolygon(terrain, height = 16, floor = 0) {
    if (!Array.isArray(terrain) || terrain.length < 2) return [];
    const bottom = height * 25 + floor;
    const top = terrain.map(([x, y]) => ({ x: x * 20, y: (height - y) * 25 }));
    return [...top, { x: top[top.length - 1].x, y: bottom }, { x: top[0].x, y: bottom }];
}

export function ridgeLabel(data) {
    if (!data || data.ridge === undefined) return "01 / RIDGELINE";
    const name = String(data.layout_name || (data.ridge > 0 ? `Ridge #${data.ridge}` : "Classic ridge")).toUpperCase();
    return data.mode === "practice" && data.bot_level ? `${name} · BOT LV ${data.bot_level}` : name;
}

// ---------- long-range artillery ----------
// Generated ridges are 160 m wide. The world is drawn at 20 px/m across and 25 px/m up,
// the same scale as the classic 800 x 400 field, so the camera shows a 40 m x 16 m window.
export const CLASSIC_FIELD = Object.freeze({ mode: "classic", w: 40, h: 16 });

export function fieldOf(data) {
    const field = data && data.field;
    if (!field || field.mode !== "long") return CLASSIC_FIELD;
    const num = (key, fallback) => Number.isFinite(Number(field[key])) ? Number(field[key]) : fallback;
    return {
        mode: "long", w: num("w", 160), h: num("h", 96), pad_x: num("pad_x", 400), pad_y: num("pad_y", 200),
        full_pull: num("full_pull", 240), min_pull: num("min_pull", 12), v_max: num("v_max", 44),
        gravity: num("gravity", 9.81), drag: num("drag", .97), shell: num("shell", .3), blast: num("blast", 1.5),
    };
}

// Long fields keep LONG_FLOOR px of soil under y = 0 so the home view is not pinned to the bottom edge.
export const LONG_FLOOR = 110;

export function fieldPixels(field) {
    return { w: field.w * 20, h: field.h * 25 + (field.mode === "long" ? LONG_FLOOR : 0) };
}

export function toScreen(field, x, y) {
    return { x: x * 20, y: (field.h - y) * 25 };
}

export function aimAngleOk(seat, angle) {
    return Number.isFinite(angle) && Math.cos(angle) * (seat === "B" ? -1 : 1) > .25 && Math.sin(angle) > -.35;
}

// Screen drag -> pad pull. Pulling back (away from the enemy) and down aims up and forward.
// Seat B mirrors x so both seats share one pad frame, exactly like the server protocol.
export function dragPull(seat, base, start, current) {
    const dx = start.x - current.x;
    const dy = current.y - start.y;
    return { x: (base ? base.x : 0) + (seat === "B" ? -dx : dx), y: (base ? base.y : 0) + dy };
}

export function padFromAim(padAngle, fraction, field) {
    const span = Math.max(0, Math.min(1, fraction)) * field.full_pull;
    return { x: Math.cos(padAngle) * span, y: Math.sin(padAngle) * span };
}

// Mirrors game/aim.jac release_long: pad pull -> world angle, launch speed and the wire pointer.
export function longAim(seat, padPull, field) {
    const span = Math.hypot(padPull.x, padPull.y);
    const padAngle = Math.atan2(padPull.y, padPull.x);
    const angle = seat === "B" ? Math.PI - padAngle : padAngle;
    const fraction = Math.min(1, span / field.full_pull);
    const clamp = span > field.full_pull ? field.full_pull / span : 1;
    const valid = Number.isFinite(span) && span >= field.min_pull && aimAngleOk(seat, angle);
    return {
        valid, angle, padAngle, fraction, power: fraction * field.v_max,
        degrees: padAngle * 180 / Math.PI,
        pointer: {
            x: Math.round((field.pad_x - padPull.x * clamp) * 1000) / 1000,
            y: Math.round((field.pad_y + padPull.y * clamp) * 1000) / 1000,
        },
    };
}

// Only the first `seconds` of flight: enough to read the launch angle and the bend of the arc,
// never the landing. Same public gravity and drag as the server shell.
export function previewArc(aim, launcher, field, seconds = .4, step = 1 / 60) {
    const points = [];
    if (!aim || !aim.valid) return points;
    let x = launcher.x, y = launcher.y;
    let vx = Math.cos(aim.angle) * aim.power, vy = Math.sin(aim.angle) * aim.power;
    const keep = Math.pow(field.drag, step);
    for (let n = 1; n * step <= seconds + 1e-9; n++) {
        vx *= keep;
        vy = vy * keep - field.gravity * step;
        x += vx * step;
        y += vy * step;
        if (n % 4 === 0) points.push({ x, y, heading: Math.atan2(vy, vx) });
    }
    return points;
}

export function clampScroll(scroll, view, world) {
    return {
        x: Math.max(0, Math.min(world.w - view.w, scroll.x)),
        y: Math.max(0, Math.min(world.h - view.h, scroll.y)),
    };
}

// Home view: own launcher a fifth in from its edge, the ground near the bottom.
export function cameraHome(seat, launcherPx, view, world) {
    const x = seat === "B" ? launcherPx.x - view.w * .8 : launcherPx.x - view.w * .2;
    return clampScroll({ x, y: launcherPx.y - view.h * .58 }, view, world);
}

// Centre the camera on a world pixel (a shell in flight, an impact, a look target).
export function cameraOn(point, view, world) {
    return clampScroll({ x: point.x - view.w / 2, y: point.y - view.h / 2 }, view, world);
}

// The overview strip across the top of the screen, in screen pixels.
export function overviewRect(view, scale = 1) {
    const h = Math.round(26 * Math.min(1.8, Math.max(1, scale)));
    const w = Math.min(view.w - 220, 560);
    return { x: Math.round((view.w - w) / 2), y: 8, w, h };
}

export function overviewToWorld(screenX, strip, world) {
    return Math.max(0, Math.min(world.w, (screenX - strip.x) / strip.w * world.w));
}

// Range marks every `every` metres from your launcher toward the enemy (public, for reading distance).
export function rangeMarks(seat, launcherX, field, every = 20) {
    const marks = [];
    const dir = seat === "B" ? -1 : 1;
    for (let d = every; d < field.w; d += every) {
        const x = launcherX + dir * d;
        if (x < 1 || x > field.w - 1) break;
        marks.push({ x, label: `${d} m` });
    }
    return marks;
}
