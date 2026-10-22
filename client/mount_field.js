// Phaser 3.90 scene mount. Jac lambdas do not bind Phaser's scene `this`,
// so the create/input callbacks live in this adapter. The projectile path,
// post pose, and reveal bodies come from the server payload. This file does
// not integrate a shot or decide a hit.
import { AUTO, Game, Scale } from "phaser";
import "../assets/field.css";
import { bodySize, pullFeedback, hudState, protocolPull, observationAt, trianglePoints, headingOf, easeOutBack, easeOutCubic, burst, stepShards, bannerFor, recordAfter, recordLabel, ridgeLines, terrainPolygon, ridgeLabel, CLASSIC_FIELD, fieldOf, fieldPixels, toScreen, dragPull, padFromAim, longAim, previewArc, clampScroll, cameraHome, cameraOn, overviewRect, overviewToWorld, rangeMarks, LONG_FLOOR, carveTerrain, craterRims } from "./presentation.js";
import { isStale, releaseAllowed, sampleAt, stepWatch } from "./playback.js";

const VIEW_W = 800;
const VIEW_H = 400;
const PULL_HELP = "Drag back and release. Keyboard: Tab to field, arrows aim, Enter fires, Escape cancels.";
const LONG_HELP = "Drag anywhere on the field to aim (pull back and down), release to set it, then FIRE or Enter. Up/Down angle, Left/Right power. Minimap or drag to look around.";
const VIEW = { w: 800, h: 400 };
const PLAY_RATE_LONG = 1.6;
// The public field the server described: classic 40 x 16 m, or a 160 m long-range ridge.
let FIELD = CLASSIC_FIELD;
const isLong = () => FIELD.mode === "long";
const RECORD_KEY = "fogshot-record";
const MAX_SHARDS = 220;

function loadRecord() {
    try { return JSON.parse(window.localStorage.getItem(RECORD_KEY) || "null"); } catch (err) { return null; }
}

function saveRecord(record) {
    try { window.localStorage.setItem(RECORD_KEY, JSON.stringify(record)); } catch (err) { /* private mode */ }
    const chip = document.getElementById("fogshot-record");
    if (chip) chip.textContent = recordLabel(record);
}

// Canvas-pixel multiplier so overlay text stays legible when the 800px field is shown small.
function uiScale(scene) {
    const width = scene.fieldParent ? scene.fieldParent.clientWidth : VIEW_W;
    return Math.min(2.4, Math.max(1, VIEW_W / Math.max(1, width)));
}

function spawn(scene, shards, palette) {
    if (scene.reducedMotion) shards = shards.slice(0, Math.ceil(shards.length / 3)).map(s => ({ ...s, vx: s.vx * .3, vy: s.vy * .3 }));
    for (const shard of shards) shard.color = palette[Math.floor(Math.random() * palette.length)];
    scene.shards = scene.shards.concat(shards).slice(-MAX_SHARDS);
}

function shake(scene, duration, intensity) {
    if (scene.reducedMotion || !scene.cameras || !scene.cameras.main) return;
    scene.cameras.main.shake(duration, intensity);
}

function flash(scene, x, y, color, radius, life = .45) {
    scene.flashes.push({ x, y, color, radius, life, age: 0 });
}

function showBanner(scene, banner, key) {
    if (!banner) return;
    scene.bannerKey = key;
    scene.banner = { ...banner, started: scene.time.now, persistent: banner.kind !== "turn" };
    const scale = uiScale(scene);
    const tint = banner.kind === "defeat" ? "#f0a48a" : banner.kind === "victory" ? "#f4d58f" : "#dfeadf";
    scene.bannerTitle.setText(banner.title).setColor(tint).setFontSize(Math.round(30 * Math.min(1.7, scale)));
    scene.bannerSub.setText(banner.sub).setFontSize(Math.round(11 * scale)).setWordWrapWidth(660);
}

function dismissBanner(scene) {
    if (scene.banner && !scene.banner.persistent && !scene.banner.leaving) scene.banner.leaving = scene.time.now;
}

// Impact of a server path's final sample: shards, flash and (for shells) a modest shake.
function impact(scene, point, weapon, heading) {
    if (weapon === "flare") {
        spawn(scene, burst(point.x, point.y, { count: 16, speed: 70, life: 1.1, size: 3, heading: -Math.PI / 2, spread: Math.PI * 1.4 }), [0xd4edce, 0xf0e9c8, 0xa9d6c2]);
        flash(scene, point.x, point.y, 0xd4edce, 46, .7);
        return;
    }
    const back = heading === null ? -Math.PI / 2 : heading + Math.PI;
    spawn(scene, burst(point.x, point.y, { count: 22, speed: 170, life: .8, size: 4.5, heading: back, spread: Math.PI * 1.3 }), [0xf2cb78, 0xe5b56c, 0xfff3d4, 0x8fa9a0]);
    // Thrown dirt: heavier, slower clods from the crater.
    if (isLong()) spawn(scene, burst(point.x, point.y, { count: 18, speed: 150, life: 1.3, size: 5, heading: -Math.PI / 2, spread: Math.PI * .9 }), [0x6b5236, 0x8a6a43, 0x4a3524, 0x5f4a33]);
    flash(scene, point.x, point.y, 0xf2cb78, 34, .4);
    shake(scene, 150, .005);
}

// Per-frame effects layer. Everything here is cosmetic and redrawn from scratch.
function animate(scene, time, delta) {
    const fx = scene.fxPen;
    if (!fx) return;
    const dt = Math.min(.05, (delta || 16) / 1000);
    const t = time / 1000;
    fx.clear();
    const hud = scene.hudPen;
    if (hud) hud.clear();
    // Sine-drifting fog wisps over the hidden half (mirrored for seat B).
    if (scene.wisps) {
        const flip = scene.seat === "B";
        const world = fieldPixels(FIELD);
        scene.wisps.forEach((wisp, i) => {
            const drift = scene.reducedMotion ? 0 : Math.sin(t * wisp.speed + wisp.phase) * wisp.amp;
            // Long fields: the wisps drift over the enemy half of the world, low over its ground.
            const baseX = isLong() ? world.w / 2 + 260 + i * (world.w / 2 - 520) / Math.max(1, scene.wisps.length - 1) : wisp.baseX;
            const baseY = isLong() ? world.h - 110 - (i % 2) * 120 - wisp.baseY * .2 : wisp.baseY;
            const x = baseX + drift;
            const span = isLong() ? world.w : VIEW_W;
            wisp.image.setScale(isLong() ? 1.7 : 1);
            wisp.image.setPosition(flip ? span - x : x, baseY + (scene.reducedMotion ? 0 : Math.sin(t * wisp.speed * 1.7 + i) * 4));
            wisp.image.setAlpha(scene.reducedMotion ? wisp.alpha : wisp.alpha * (.75 + .25 * Math.sin(t * .6 + wisp.phase)));
        });
    }
    const launch = scene.launch || launcherOf(scene);
    const finished = scene.fieldParent && scene.fieldParent.dataset.phase === "finished";
    // Your-turn beacon: a breathing ring and three orbiting chevrons around the launcher.
    if (scene.yourTurn && !finished) {
        const breathe = scene.reducedMotion ? .5 : .5 + .5 * Math.sin(t * 3.2);
        fx.lineStyle(2, 0xf1d18b, .25 + .35 * breathe);
        fx.strokeCircle(launch.x, launch.y, 26 + breathe * 5);
        if (!scene.reducedMotion && !scene.activePull) {
            for (let k = 0; k < 3; k++) {
                const a = t * 1.4 + k * (Math.PI * 2 / 3);
                const r = 36;
                const [n, l, rr] = trianglePoints(launch.x + Math.cos(a) * r, launch.y + Math.sin(a) * r, 4, a + Math.PI / 2);
                fx.fillStyle(0xf1d18b, .55); fx.fillTriangle(n.x, n.y, l.x, l.y, rr.x, rr.y);
            }
        }
    }
    // First-shot coaching: a ghost pull eases back from the launcher until the first drag.
    if (scene.yourTurn && !scene.activePull && scene.coach && !finished) {
        const dir = scene.seat === "B" ? 1 : -1;
        const cycle = scene.reducedMotion ? .8 : (t % 1.6) / 1.6;
        const e = easeOutCubic(Math.min(1, cycle / .75));
        const gx = launch.x + dir * 62 * e, gy = launch.y + 30 * e;
        const fade = cycle > .8 ? 1 - (cycle - .8) / .2 : 1;
        fx.lineStyle(1.5, 0xf1d18b, .5 * fade);
        fx.lineBetween(launch.x, launch.y, gx, gy);
        fx.fillStyle(0xf1d18b, .9 * fade); fx.fillCircle(gx, gy, 5);
        fx.lineStyle(1, 0xf1d18b, .4 * fade); fx.strokeCircle(gx, gy, 9 + 4 * e);
        const half = scene.coachLabel.width / 2 + 6;
        const lx = Math.min(VIEW_W - half, Math.max(half, launch.x + dir * 66));
        scene.coachLabel.setVisible(true).setPosition(lx, launch.y - 22 - 4 * uiScale(scene)).setAlpha(.6 + .4 * fade);
    } else if (scene.coachLabel) {
        scene.coachLabel.setVisible(false);
    }
    // Aim chevrons: triangles rotated to the launch angle, pulsing outward with a sine wave.
    const pull = scene.activePull;
    const shown = isLong() && !finished ? currentAim(scene, pull) : pull ? currentAim(scene, pull) : null;
    if (shown && !(isLong() && scene.shot && !scene.landed)) {
        const aim = shown;
        const heading = -aim.angle; // world y-up angle -> screen y-down angle
        const color = aim.valid ? (aim.locked ? 0xa9d6c2 : 0xf1d18b) : 0xb98472;
        if (isLong() && aim.valid && aim.guide.length) {
            // Partial trajectory: the first half second of the arc as a dotted line, then chevrons.
            fx.lineStyle(1.5, color, .35);
            fx.beginPath(); fx.moveTo(launch.x, launch.y);
            aim.guide.forEach(p => fx.lineTo(p.x, p.y));
            fx.strokePath();
        }
        aim.guide.forEach((point, n) => {
            const wave = scene.reducedMotion ? .6 : .5 + .5 * Math.sin(t * 9 - n * .9);
            const fade = isLong() ? 1 - n / (aim.guide.length + 1) : 1;
            const [a, b, c] = trianglePoints(point.x, point.y, 2.6 + wave * 1.6 + aim.pullFraction * 1.2, point.heading ?? heading);
            fx.fillStyle(color, (.45 + .55 * wave) * fade); fx.fillTriangle(a.x, a.y, b.x, b.y, c.x, c.y);
        });
        const pct = isLong() ? (aim.pullFraction * 100).toFixed(1) : Math.round(aim.pullFraction * 100);
        const degrees = isLong() ? (aim.angle * 180 / Math.PI > 90 ? 180 - aim.angle * 180 / Math.PI : aim.angle * 180 / Math.PI).toFixed(1) : Math.round(aim.angle * 180 / Math.PI);
        scene.aimLabel.setVisible(true).setFontSize(Math.round(10 * uiScale(scene)))
            .setText(aim.valid ? `${pct}%  ${degrees}°` : "AIM FORWARD")
            .setColor(aim.valid ? "#f1d18b" : "#e0a08e")
            .setPosition(launch.x, launch.y - 44 - 4 * uiScale(scene));
    } else if (scene.aimLabel) {
        scene.aimLabel.setVisible(false);
    }
    // Fading comet trail behind the shell.
    if (scene.trail && scene.trail.length > 1 && !scene.landed) {
        for (let i = 1; i < scene.trail.length; i++) {
            const a = scene.trail[i - 1], b = scene.trail[i];
            const k = i / scene.trail.length;
            fx.lineStyle(1 + k * 4, (scene.pathWeapon || scene.weapon) === "flare" ? 0xd4edce : 0xf2cb78, k * .45);
            fx.lineBetween(a.x, a.y, b.x, b.y);
        }
    }
    // Launch recoil ring.
    if (scene.recoil !== null && scene.recoil !== undefined) {
        const age = (time - scene.recoil) / 1000;
        if (age < .35) {
            fx.lineStyle(3 * (1 - age / .35), 0xf1d18b, 1 - age / .35);
            fx.strokeCircle(launch.x, launch.y, 10 + easeOutCubic(age / .35) * 30);
        } else scene.recoil = null;
    }
    // Flashes and triangle shards.
    scene.flashes = scene.flashes.filter(f => (f.age += dt) < f.life);
    for (const f of scene.flashes) {
        const k = f.age / f.life;
        fx.fillStyle(f.color, (1 - k) * .35); fx.fillCircle(f.x, f.y, f.radius * easeOutCubic(k));
        fx.lineStyle(2, f.color, (1 - k) * .8); fx.strokeCircle(f.x, f.y, f.radius * (.4 + easeOutCubic(k)));
    }
    if (scene.shards.length) {
        scene.shards = stepShards(scene.shards, dt);
        for (const s of scene.shards) {
            const [a, b, c] = trianglePoints(s.x, s.y, s.size, s.rot);
            fx.fillStyle(s.color, Math.max(0, 1 - s.age / s.life));
            fx.fillTriangle(a.x, a.y, b.x, b.y, c.x, c.y);
        }
    }
    // Banner: pops in with a back-eased scale, turn banners fade after a beat.
    const banner = scene.banner;
    if (banner) {
        const age = (time - banner.started) / 1000;
        let alpha = Math.min(1, age / .2);
        if (!banner.persistent && age > 1.8 && !banner.leaving) banner.leaving = time;
        if (banner.leaving) alpha = Math.max(0, 1 - (time - banner.leaving) / 350);
        if (alpha <= 0 && banner.leaving) {
            scene.banner = null;
            scene.bannerTitle.setVisible(false); scene.bannerSub.setVisible(false);
        } else {
            const pop = scene.reducedMotion ? 1 : easeOutBack(Math.min(1, age / .45));
            const y = banner.persistent ? 150 : 88;
            scene.bannerTitle.setVisible(true).setAlpha(alpha).setScale(pop).setPosition(VIEW_W / 2, y);
            scene.bannerSub.setVisible(true).setAlpha(alpha).setPosition(VIEW_W / 2, y + scene.bannerTitle.displayHeight / 2 + scene.bannerSub.height / 2 + 4);
            const w = Math.max(scene.bannerTitle.displayWidth, scene.bannerSub.width) + 48;
            const h = scene.bannerTitle.displayHeight + scene.bannerSub.height + 22;
            hud.fillStyle(0x081a22, .72 * alpha);
            hud.fillRoundedRect(VIEW_W / 2 - w / 2, y - scene.bannerTitle.displayHeight / 2 - 9, w, h, 8);
            const edge = banner.kind === "defeat" ? 0xf0a48a : banner.kind === "victory" ? 0xf4d58f : 0x8fc5b6;
            hud.lineStyle(1, edge, .6 * alpha);
            hud.strokeRoundedRect(VIEW_W / 2 - w / 2, y - scene.bannerTitle.displayHeight / 2 - 9, w, h, 8);
            if (banner.persistent && !scene.reducedMotion) {
                // Slow rotating triangle crest on either side of the result.
                for (const side of [-1, 1]) {
                    const cx = VIEW_W / 2 + side * (w / 2 + 18), spin = t * 1.2 * side;
                    const [a, b, c] = trianglePoints(cx, y, 9, spin);
                    hud.lineStyle(1.5, edge, .8 * alpha); hud.strokeTriangle(a.x, a.y, b.x, b.y, c.x, c.y);
                }
            }
        }
    }
    if (isLong() && hud) drawOverview(scene, hud, t);
}

// Minimap strip pinned to the top of the screen: the whole public ridge, both launchers,
// your outpost, the shell in flight, the open reveal and the camera window. Tap or drag it to look.
function drawOverview(scene, hud, t) {
    const world = fieldPixels(FIELD);
    const strip = overviewRect(VIEW, uiScale(scene));
    scene.strip = strip;
    const sx = x => strip.x + x / world.w * strip.w;
    const top = 18; // metres of terrain shown in the strip
    const sy = y => strip.y + strip.h - Math.max(0, Math.min(top, y)) / top * (strip.h - 4);
    hud.fillStyle(0x081a22, .78); hud.fillRoundedRect(strip.x - 4, strip.y - 3, strip.w + 8, strip.h + 6, 5);
    hud.lineStyle(1, 0x5f8a83, .7); hud.strokeRoundedRect(strip.x - 4, strip.y - 3, strip.w + 8, strip.h + 6, 5);
    const terrain = scene.terrain;
    if (Array.isArray(terrain) && terrain.length > 1) {
        hud.fillStyle(0x2c5058, 1);
        hud.beginPath(); hud.moveTo(sx(Math.max(0, terrain[0][0]) * 20), strip.y + strip.h);
        for (const [x, y] of terrain) if (x >= 0 && x <= FIELD.w) hud.lineTo(sx(x * 20), sy(y));
        hud.lineTo(sx(world.w), strip.y + strip.h); hud.closePath(); hud.fillPath();
    }
    // The enemy half is fogged on the map too.
    const enemyLeft = scene.seat === "B" ? strip.x : strip.x + strip.w / 2;
    hud.fillStyle(0x091d28, .45); hud.fillRect(enemyLeft, strip.y, strip.w / 2, strip.h);
    const own = launcherWorld(scene);
    const foe = { x: FIELD.w - own.x, y: own.y };
    hud.fillStyle(0xf1d18b, 1); hud.fillTriangle(sx(own.x * 20) - 4, sy(own.y) + 3, sx(own.x * 20) + 4, sy(own.y) + 3, sx(own.x * 20), sy(own.y) - 5);
    hud.fillStyle(0xe0a08e, .85); hud.fillTriangle(sx(foe.x * 20) - 4, sy(foe.y) + 3, sx(foe.x * 20) + 4, sy(foe.y) + 3, sx(foe.x * 20), sy(foe.y) - 5);
    const core = ownBodies(scene.view).find(body => body.role === "core");
    if (core) { hud.fillStyle(core.alive === false ? 0x6b7973 : 0x8fc5b6, 1); hud.fillRect(sx(core.x * 20) - 2, sy(core.y) - 2, 4, 4); }
    if (scene.reveal) { hud.lineStyle(1.5, 0xf0d095, .9); hud.strokeCircle(sx(scene.reveal.x * 20), sy(scene.reveal.y), 4 + Math.sin(t * 6) * 1); }
    if (scene.shot && !scene.landed) { hud.fillStyle(0xfff3d4, 1); hud.fillCircle(sx(scene.shot.x), Math.max(strip.y + 2, sy(FIELD.h - scene.shot.y / 25)), 2.5); }
    const cam = scene.cameras.main;
    hud.lineStyle(1.5, 0xdfeadf, .8);
    hud.strokeRect(sx(cam.scrollX), strip.y - 1, VIEW.w / world.w * strip.w, strip.h + 2);
}

// Long-range camera: follow the shell, hold on the burst, then return home (or stay where you looked).
function steerCamera(scene, time, delta) {
    const cam = scene.cameras.main;
    const world = fieldPixels(FIELD);
    const parent = scene.fieldParent;
    let mode = "home";
    let target = null;
    if (scene.panDrag || scene.stripDrag) {
        mode = "look";
    } else if (scene.shot && !scene.landed) {
        mode = "follow";
        target = cameraOn(scene.shot, VIEW, world);
    } else if (scene.landedAt !== null && time - scene.landedAt < 1400 && scene.landPoint) {
        mode = "impact";
        target = cameraOn({ x: scene.landPoint.x, y: scene.landPoint.y - 70 }, VIEW, world);
    } else if (scene.lookAt) {
        mode = "look";
        target = cameraOn(scene.lookAt, VIEW, world);
    } else {
        target = cameraHome(scene.seat, launcherOf(scene), VIEW, world);
    }
    if (target) {
        const k = scene.reducedMotion || scene.snapCamera ? 1 : 1 - Math.exp(-(delta || 16) / 1000 * (mode === "follow" ? 8 : 4.5));
        scene.snapCamera = false;
        cam.setScroll(cam.scrollX + (target.x - cam.scrollX) * k, cam.scrollY + (target.y - cam.scrollY) * k);
    }
    if (parent) {
        if (parent.dataset.camera !== mode) parent.dataset.camera = mode;
        parent.dataset.cameraX = String(Math.round(cam.scrollX));
        parent.dataset.cameraY = String(Math.round(cam.scrollY));
    }
}

function worldToScreen(x, y) {
    return toScreen(FIELD, x, y);
}

function ownBodies(view) {
    if (!view || !view.own) {
        return [];
    }
    return view.own;
}

function revealedBodies(view) {
    if (!view || !view.reveal || !view.reveal.bodies) {
        return [];
    }
    return view.reveal.bodies;
}

// A fragment of a broken block: the parent's material, darker, with a cracked face.
function drawDebris(pen, body, friendly) {
    if (body.alive === false) return;
    const center = worldToScreen(body.x, body.y);
    if (center.x < -40 || center.x > fieldPixels(FIELD).w + 40) return;
    const { width, height } = bodySize(body);
    if (!width || !height) return;
    const stone = body.role === "debris-stone";
    const tone = stone ? (friendly ? 0x3d5a5f : 0x766a59) : (friendly ? 0x34564e : 0x7a5d3b);
    pen.save();
    pen.translateCanvas(center.x, center.y);
    pen.rotateCanvas(-body.angle);
    pen.fillStyle(tone, 1);
    pen.fillRect(-width / 2, -height / 2, width, height);
    pen.lineStyle(1, friendly ? 0x8fc5b6 : 0xe5b56c, .45);
    pen.strokeRect(-width / 2, -height / 2, width, height);
    pen.lineStyle(1, 0x0c1c22, .6);
    pen.lineBetween(-width / 2, -height * .1, width * .1, height / 2);
    pen.restore();
}

function drawBodies(pen, bodies, friendly, scene) {
    for (const body of bodies) {
        if (["ground", "marker", "launcher"].includes(body.role)) continue;
        // Shattered blocks are gone from the world; do not leave a grey ghost.
        if (body.alive === false && ["timber", "stone", "spur"].includes(body.role)) continue;
        if (String(body.role || "").startsWith("debris")) { drawDebris(pen, body, friendly); continue; }
        const center = worldToScreen(body.x, body.y);
        if (center.x < -40 || center.x > fieldPixels(FIELD).w + 40) continue;
        const { width, height } = bodySize(body);
        if (!width || !height) continue;
        const falling = body.role === "post" && scene.collapseId === body.id && typeof scene.collapseAngle === "number";
        pen.save();
        pen.translateCanvas(center.x, center.y);
        pen.rotateCanvas(-(falling ? scene.collapseAngle : body.angle));
        const edge = friendly ? 0x8fc5b6 : 0xe5b56c;
        const tone = { footing: friendly ? 0x23434b : 0x4f4434, plinth: friendly ? 0x2c5058 : 0x66573f, stone: friendly ? 0x46666b : 0x857865, timber: friendly ? 0x3c6158 : 0x8a6a43, spur: friendly ? 0x2a4a50 : 0x5d5040 }[body.role];
        const dark = body.alive === false ? 0x39494a : tone ?? (friendly ? 0x355d63 : 0x7e694b);
        pen.fillStyle(dark, 1);
        pen.fillRect(-width / 2, -height / 2, width, height);
        // All material detail stays inside the server-sized silhouette.
        const inset = Math.min(2, width / 5, height / 5);
        pen.fillStyle(edge, 0.85);
        pen.fillRect(-width / 2, -height / 2, inset, height);
        pen.fillRect(-width / 2, -height / 2, width, inset);
        if (body.role === "core" && width > 10 && height > 10) {
            pen.fillStyle(0x102e36, 1);
            pen.fillRect(-width * .3, -height * .3, width * .6, height * .6);
            pen.fillStyle(body.alive === false ? 0x4b6260 : 0xf0cb7b, 1);
            pen.fillCircle(0, 0, Math.min(width, height) * .18);
            pen.fillStyle(0xf0e9c8, .85);
            for (const x of [-.35, .35]) for (const y of [-.35, .35]) pen.fillCircle(x * width, y * height, Math.min(1.2, inset));
        } else if (body.role === "stone" && width > 6 && height > 6) {
            // Masonry: staggered courses.
            pen.lineStyle(1, edge, .4);
            let row = 0;
            for (let y = -height / 2 + 6; y < height / 2 - 1; y += 6, row++) {
                pen.lineBetween(-width / 2 + inset, y, width / 2, y);
                for (let x = -width / 2 + (row % 2 ? 5 : 9); x < width / 2 - 2; x += 9) pen.lineBetween(x, y - 6, x, y);
            }
        } else if (body.role === "timber" && width > 4 && height > 4) {
            // Timber: grain lines along the long axis plus an X brace.
            pen.lineStyle(1, edge, .45);
            if (height >= width) for (let x = -width / 2 + 4; x < width / 2 - 1; x += 4) pen.lineBetween(x, -height / 2 + inset, x, height / 2);
            else for (let y = -height / 2 + 4; y < height / 2 - 1; y += 4) pen.lineBetween(-width / 2 + inset, y, width / 2, y);
            if (width > 9 && height > 9) { pen.lineStyle(1, edge, .3); pen.lineBetween(-width / 2, -height / 2, width / 2, height / 2); pen.lineBetween(width / 2, -height / 2, -width / 2, height / 2); }
        } else if (body.role === "footing" || body.role === "spur") {
            // Rubble footing: a row of small triangles along the top edge.
            pen.fillStyle(edge, .35);
            for (let x = -width / 2 + 5; x < width / 2 - 3; x += 9) pen.fillTriangle(x - 3, -height / 2 + inset + 4, x + 3, -height / 2 + inset + 4, x, -height / 2 + inset);
        } else if (height > 12 && width > 4) {
            pen.lineStyle(1, edge, .65);
            for (let y = -height / 2 + 7; y < height / 2 - 6; y += 12) {
                pen.lineBetween(-width / 2 + inset, y, width / 2 - inset, y + 6);
            }
        }
        pen.restore();
    }
}

// Screen y of the public ground under screen x (classic ground is the SVG soil line).
function groundScreenY(terrain, x) {
    if (!Array.isArray(terrain) || terrain.length < 2) return 397;
    const wx = x / 20;
    for (let i = 1; i < terrain.length; i++) {
        const [x0, y0] = terrain[i - 1], [x1, y1] = terrain[i];
        if (wx <= x1) {
            const t = x1 === x0 ? 0 : Math.min(1, Math.max(0, (wx - x0) / (x1 - x0)));
            const gy = y0 + (y1 - y0) * t;
            if (isLong()) return (FIELD.h - gy) * 25;
            return gy <= 0.001 ? 397 : (1 - gy / 16) * 400;
        }
    }
    return isLong() ? FIELD.h * 25 : 397;
}

function launcherWorld(scene) {
    for (const body of ownBodies(scene.view)) {
        if (body.role === "launcher") return { x: body.x, y: body.y };
    }
    return { x: scene.seat === "B" ? FIELD.w - 6 : 6, y: 4 };
}

function launcherOf(scene) {
    const spot = launcherWorld(scene);
    return worldToScreen(spot.x, spot.y);
}

// Your launcher pad is reinforced (never cratered); the enemy pad is secret, so it is not used.
function ownPads(data) {
    const spot = (data.view && data.view.own || []).find(body => body.role === "launcher");
    return spot && Number.isFinite(spot.x) ? [spot.x] : [];
}

// Public terrain and seeded distant ridgelines. Redrawn only when the ridge changes.
function paintLand(scene, data) {
    const pen = scene.landPen;
    if (!pen) return;
    const craters = Array.isArray(data.craters) ? data.craters : [];
    const key = `${data.ridge ?? 0}:${data.epoch ?? 0}:${FIELD.mode}:${scene.seat || ""}:${JSON.stringify(craters)}`;
    if (scene.landKey === key) return;
    scene.landKey = key;
    pen.clear();
    const far = scene.farPen;
    if (far) far.clear();
    const world = fieldPixels(FIELD);
    // Long fields: distant ridgelines on a slow parallax layer, sized to cover the camera's travel.
    const parallax = .25;
    const farPen = isLong() && far ? far : pen;
    const farWidth = isLong() ? VIEW_W + (world.w - VIEW_W) * parallax : VIEW_W;
    const lift = isLong() ? (world.h - VIEW_H) * parallax : 0;
    const lines = ridgeLines(Number(data.ridge || 0), 3, 16, farWidth);
    const tones = [0x2e5360, 0x264753, 0x1f3d48];
    lines.forEach((points, i) => {
        farPen.fillStyle(tones[i % tones.length], .6 + i * .12);
        farPen.beginPath(); farPen.moveTo(0, 400 + lift);
        for (const p of points) farPen.lineTo(p.x, p.y + lift);
        farPen.lineTo(farWidth, 400 + lift); farPen.closePath(); farPen.fillPath();
        farPen.lineStyle(1.2, 0x9fbfb2, .14 + i * .05);
        farPen.beginPath(); farPen.moveTo(points[0].x, points[0].y + lift);
        for (const p of points) farPen.lineTo(p.x, p.y + lift);
        farPen.strokePath();
    });
    for (const label of scene.rangeLabels || []) label.setVisible(false);
    // Craters the server let this seat see, cut into the public ridge (your own pad never caves).
    const pads = ownPads(data);
    const land = craters.length ? carveTerrain(data.terrain, craters, pads) : data.terrain;
    const ground = terrainPolygon(land, FIELD.h, isLong() ? LONG_FLOOR : 0);
    if (ground.length && Number(data.ridge || 0) > 0) {
        pen.fillStyle(0x16303a, 1);
        pen.beginPath(); pen.moveTo(ground[0].x, ground[0].y);
        for (const p of ground) pen.lineTo(p.x, p.y);
        pen.closePath(); pen.fillPath();
        // Strata: faint offset copies of the crest give the soil some depth.
        for (const [drop, alpha] of [[7, .18], [15, .1]]) {
            pen.lineStyle(1, 0x5f8a83, alpha);
            pen.beginPath(); pen.moveTo(ground[0].x, ground[0].y + drop);
            for (const p of ground.slice(0, -2)) pen.lineTo(p.x, p.y + drop);
            pen.strokePath();
        }
        pen.lineStyle(3, 0x82a99a, .5);
        pen.beginPath(); pen.moveTo(ground[0].x, ground[0].y);
        for (const p of ground.slice(0, -2)) pen.lineTo(p.x, p.y);
        pen.strokePath();
        // Scorched crater bowls with a few thrown-up clods on the lips.
        for (const rim of craterRims(data.terrain, craters, pads, 2.5, FIELD.h)) {
            pen.fillStyle(0x0f2229, .9);
            pen.beginPath(); pen.moveTo(rim[0].x, rim[0].y);
            for (const p of rim) pen.lineTo(p.x, p.y + 5);
            pen.lineTo(rim[rim.length - 1].x, rim[rim.length - 1].y); pen.closePath(); pen.fillPath();
            pen.lineStyle(3, 0x4a3524, .85);
            pen.beginPath(); pen.moveTo(rim[0].x, rim[0].y);
            for (const p of rim) pen.lineTo(p.x, p.y);
            pen.strokePath();
            const a = rim[0], b = rim[rim.length - 1];
            pen.fillStyle(0x6b5236, .9);
            for (const [p, side] of [[a, -1], [b, 1]]) {
                pen.fillTriangle(p.x - 6, p.y + 1, p.x + 6, p.y + 1, p.x + side * 2, p.y - 5);
                pen.fillCircle(p.x + side * 7, p.y - 1, 2);
            }
        }
    }
    const crest = scene.crestPen;
    if (crest) crest.clear();
    if (crest && isLong() && ground.length) {
        crest.lineStyle(2, 0x82a99a, .35);
        crest.beginPath(); crest.moveTo(ground[0].x, ground[0].y);
        for (const p of ground.slice(0, -2)) crest.lineTo(p.x, p.y);
        crest.strokePath();
    }
    scene.terrain = land;
    if (isLong() && Array.isArray(data.terrain)) {
        // Range marks from your launcher: read distance, then pick angle and power.
        const spot = launcherWorld(scene);
        const marks = rangeMarks(scene.seat, spot.x, FIELD);
        marks.slice(0, (scene.rangeLabels || []).length).forEach((mark, i) => {
            const at = worldToScreen(mark.x, 0);
            const gy = groundScreenY(land, at.x);
            pen.lineStyle(2, 0xb8d6c6, .35);
            pen.lineBetween(at.x, gy - 12, at.x, gy + 2);
            scene.rangeLabels[i].setText(mark.label).setFontSize(Math.round(10 * Math.min(1.8, uiScale(scene)))).setPosition(at.x, gy - 16 - 12 * Math.min(1.8, uiScale(scene))).setAlpha(.75).setVisible(true);
        });
        // The midline: no man's land starts here.
        const mid = worldToScreen(FIELD.w / 2, 0);
        const my = groundScreenY(land, mid.x);
        for (let y = my - 200; y < my; y += 14) { pen.lineStyle(1, 0xe2d4a8, .18); pen.lineBetween(mid.x, y, mid.x, y + 7); }
    }
}

function drawLauncher(pen, scene, pull) {
    const launch = launcherOf(scene);
    scene.launch = launch;
    const direction = scene.seat === "B" ? -1 : 1;
    // Indestructible launch utility; its decorative pedestal is not a target.
    // On generated ridges the tower reaches down to the public ground under it.
    const foot = Math.max(launch.y + 60, groundScreenY(scene.terrain, launch.x) - 1);
    const tall = foot - (launch.y + 29);
    pen.fillStyle(0x0c2730, 1);
    pen.fillRect(launch.x - 19, launch.y + 29, 38, tall);
    pen.lineStyle(2, 0x456d71, 1);
    for (let top = launch.y + 32; top < foot - 8; top += 61) {
        const bottom = Math.min(foot - 4, top + 61);
        pen.lineBetween(launch.x - 15, bottom, launch.x + 15, top);
        pen.lineBetween(launch.x + 15, bottom, launch.x - 15, top);
    }
    pen.fillStyle(0x244751, 1);
    pen.fillRoundedRect(launch.x - 30, launch.y + 23, 60, 12, 3);
    pen.fillStyle(0x83b8a9, 1);
    pen.fillRect(launch.x - 30, launch.y + 23, 60, 3);
    pen.lineStyle(6, 0x416870, 1);
    pen.lineBetween(launch.x - 13, launch.y + 23, launch.x - 8, launch.y - 10);
    pen.lineBetween(launch.x + 13, launch.y + 23, launch.x + 8, launch.y - 10);
    pen.lineStyle(2, 0xd8c48b, 1);
    const aim = currentAim(scene, pull);
    const tug = aim ? (isLong() ? aim.pullFraction * 30 : Math.min(30, aim.power * 4)) : 0;
    const pouch = aim ? { x: launch.x - Math.cos(aim.angle) * tug, y: launch.y + Math.sin(aim.angle) * tug } : launch;
    pen.lineBetween(launch.x - 8, launch.y - 10, pouch.x, pouch.y);
    pen.lineBetween(launch.x + 8, launch.y - 10, pouch.x, pouch.y);
    pen.fillStyle(0x101e27, 1); pen.fillCircle(pouch.x, pouch.y, 7);
    pen.fillStyle(0xf1d18b, 1); pen.fillCircle(pouch.x - 1, pouch.y - 1, 4);
    pen.lineStyle(1, scene.yourTurn ? 0xa9d6c2 : 0x5c8080, .7);
    pen.strokeCircle(launch.x, launch.y, 24);
    pen.fillStyle(scene.powered ? 0xa5ceaf : 0x6b7973, 1);
    pen.fillCircle(launch.x + direction * 22, launch.y + 29, 3);
    if (aim) {
        pen.lineStyle(2, aim.valid ? 0xf1d18b : 0xb98472, .9);
        pen.beginPath(); pen.arc(launch.x, launch.y, 29, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * aim.pullFraction); pen.strokePath();
    }
}

// Aim feedback in one shape for both modes. Long range: `pull` is the pad pull while dragging;
// otherwise the locked aim is shown on your turn.
function currentAim(scene, pull) {
    if (!isLong()) return pull ? pullFeedback(scene.seat, pull, launcherWorld(scene)) : null;
    const padPull = pull || (scene.yourTurn ? scene.lockedPull : null);
    if (!padPull) return null;
    const aim = longAim(scene.seat, padPull, FIELD);
    const spot = launcherWorld(scene);
    const guide = previewArc(aim, spot, FIELD).map(p => ({ ...worldToScreen(p.x, p.y), heading: -p.heading }));
    return { ...aim, pullFraction: aim.fraction, guide, locked: !pull };
}

function expireObservation(scene) {
    if (!scene.reveal || Date.now() < scene.reveal.until) return;
    scene.view = { ...scene.view, reveal: null };
    scene.reveal = null;
    scene.path = null;
    scene.shot = null;
    scene.collapse = null;
    scene.collapseAngle = null;
    scene.collapseId = "";
    const parent = scene.fieldParent;
    Object.assign(parent.dataset, { reveal: "closed", shotScreenX: "", shotTime: "" });
    if (scene.seat !== "B") Object.assign(parent.dataset, { broken: "false", postAngle: "0" });
    const observation = document.getElementById("fogshot-observation");
    if (observation) observation.textContent = "ENEMY STRUCTURES HIDDEN";
}

function paint(scene, pull) {
    expireObservation(scene);
    const pen = scene.fogPen;
    if (!pen) return;
    pen.clear();
    scene.fogBank.setFlipX(scene.seat === "B");
    scene.fogBank.setVisible(!isLong());
    scene.fogEdge.setVisible(isLong());
    scene.fogVeil.setVisible(isLong());
    if (isLong()) {
        const world = fieldPixels(FIELD);
        const mid = world.w / 2;
        const flip = scene.seat === "B";
        // The edge ramps in over 15 m from the midline, then an even veil to the far end.
        scene.fogEdge.setFlipX(flip).setDisplaySize(300, world.h).setPosition(flip ? mid - 300 + 0 : mid, 0);
        scene.fogVeil.setSize(mid - 300, world.h).setPosition(flip ? 0 : mid + 300, 0);
        if (flip) scene.fogEdge.setPosition(mid - 300, 0);
    }
    const patch = scene.reveal;
    scene.effectLive = false;
    if (patch && scene.view && scene.view.reveal) {
        const p = worldToScreen(patch.x, patch.y);
        const w = patch.radius * 40, h = patch.radius * 50;
        pen.fillStyle(0xbdcbb0, .12);
        pen.fillRect(p.x - w / 2, p.y - h / 2, w, h);
        pen.lineStyle(1, 0xe2d4a8, .45);
        pen.strokeRect(p.x - w / 2, p.y - h / 2, w, h);
        const age = (scene.time.now - patch.started) / 1000;
        // A finite observation pulse, placed only at a server-authorized reveal.
        if (!scene.reducedMotion && age < .8) {
            scene.effectLive = true;
            pen.lineStyle(2, 0xf0d095, (1 - age / .8) * .7);
            pen.strokeCircle(p.x, p.y, 8 + age * 36);
            pen.fillStyle(0xf0d095, 1 - age / .8);
            for (let i = 0; i < 10; i++) {
                const angle = i * 2.4;
                const x = Math.cos(angle) * age * 30, y = Math.sin(angle) * age * 30;
                if (Math.abs(x) < w / 2 && Math.abs(y) < h / 2) pen.fillCircle(p.x + x, p.y + y, 1.5);
            }
        }
    }
    drawBodies(pen, ownBodies(scene.view), true, scene);
    drawBodies(pen, revealedBodies(scene.view), false, scene);
    drawLauncher(pen, scene, pull);
    if (scene.shot && !scene.landed) {
        const heading = scene.heading;
        if (heading !== null && heading !== undefined) {
            const back = { x: scene.shot.x - Math.cos(heading) * 15, y: scene.shot.y - Math.sin(heading) * 15 };
            const nx = -Math.sin(heading) * 4, ny = Math.cos(heading) * 4;
            pen.fillStyle(scene.weapon === "flare" ? 0xd4edce : 0xf2cb78, .5);
            pen.fillTriangle(scene.shot.x + nx, scene.shot.y + ny, scene.shot.x - nx, scene.shot.y - ny, back.x, back.y);
        }
        if (!scene.reducedMotion) {
            pen.fillStyle(0xf2cb78, .12); pen.fillCircle(scene.shot.x, scene.shot.y, 15);
            pen.fillStyle(0xf2cb78, .2); pen.fillCircle(scene.shot.x, scene.shot.y, 9);
        }
        pen.fillStyle(0x172c34, 1); pen.fillCircle(scene.shot.x, scene.shot.y, 6);
        pen.fillStyle(scene.weapon === "flare" ? 0xd4edce : 0xf2cb78, 1);
        pen.fillCircle(scene.shot.x, scene.shot.y, 4);
        pen.fillStyle(0xfff3d4, 1); pen.fillCircle(scene.shot.x - 1, scene.shot.y - 1, 1.5);
    }
    const core = ownBodies(scene.view).find(body => body.role === "core");
    scene.coreLabel.setVisible(Boolean(core));
    if (core) {
        const point = worldToScreen(core.x, core.y);
        scene.coreLabel.setPosition(point.x, point.y - bodySize(core).height / 2 - scene.coreLabel.height / 2 - 4);
        scene.coreLabel.setText(core.alive === false ? "YOUR CORE / LOST" : "YOUR CORE");
    }
    const origin = launcherOf(scene);
    scene.launchLabel.setPosition(origin.x, origin.y + 49);
    const phase = scene.fieldParent ? scene.fieldParent.dataset.phase : "";
    const botThinking = scene.fieldParent && scene.fieldParent.dataset.botThinking === "true";
    const aimWord = isLong() ? (scene.lockedPull ? "AIM SET / FIRE" : "DRAG TO AIM") : "PULL TO FIRE";
    scene.launchLabel.setText(phase === "finished" ? "DUEL OVER" : scene.yourTurn ? aimWord : botThinking ? "BOT AIMING" : "STAND BY");
    scene.activePull = pull || null;
}

function renderHud(data) {
    const status = hudState(data);
    const put = (id, text) => { const element = document.getElementById(id); if (element && element.textContent !== text) element.textContent = text; };
    const rematch = document.getElementById("fogshot-rematch");
    if (rematch) { rematch.disabled = data.phase !== "finished"; rematch.title = data.phase === "finished" ? "Play another duel (R)" : "Available after the duel"; rematch.classList.toggle("is-ready", data.phase === "finished"); }
    put("fogshot-room", data.mode === "practice" ? "Practice bot" : data.room || "------");
    put("fogshot-ridge", ridgeLabel(data));
    put("fogshot-turn", status.turn);
    put("fogshot-weapon", status.weapon);
    put("fogshot-supply", status.supply);
    put("fogshot-cores", `Own: ${status.core}\nEnemy: ${status.enemy}`);
    put("fogshot-observation", data.view && data.view.reveal ? "OBSERVATION OPEN / REMEMBER THIS" : "ENEMY STRUCTURES HIDDEN");
    const field = document.getElementById("fogshot-field");
    if (!data.your_turn) put("fogshot-pull", status.turn + (data.phase === "finished" ? ". Rematch starts another duel." : ". Wait for your turn."));
    else if (field?.dataset.yourTurn !== "true" || field?.dataset.epoch !== String(data.epoch)) put("fogshot-pull", isLong() ? LONG_HELP : PULL_HELP);
}

export function practiceFromLocation() {
    return new URLSearchParams(window.location.search).get("practice") === "1";
}

export function cancelField() {
    window.dispatchEvent(new Event("blur"));
    const button = document.getElementById("fogshot-rematch");
    if (button) button.disabled = true;
}

// `?ridge=N` replays a shared ridge (0 is the classic fixture); a missing value draws a fresh one.
export function ridgeFromLocation() {
    const raw = new URLSearchParams(window.location.search).get("ridge");
    return raw !== null && /^\d{1,5}$/.test(raw) ? Number(raw) : -1;
}

export function navigateMode(practice) {
    const url = new URL(window.location.href);
    const ridge = ridgeFromLocation();
    url.search = "";
    if (ridge >= 0) url.searchParams.set("ridge", String(ridge));
    url.hash = "";
    if (practice) url.searchParams.set("practice", "1");
    window.location.assign(url.toString());
}

export function roomFromLocation() {
    const code = new URLSearchParams(window.location.search).get("room") || "";
    return /^[0-9a-f]{6}$/.test(code) ? code : "";
}

export function publishRoom(code) {
    if (!/^[0-9a-f]{6}$/.test(code || "")) {
        return;
    }
    const url = new URL(window.location.href);
    url.searchParams.set("room", code);
    window.history.replaceState(null, "", `${url.pathname}?${url.searchParams.toString()}`);
}

function remember(parent, data) {
    renderHud(data);
    if (data.room) {
        parent.dataset.room = data.room;
    }
    parent.dataset.mode = data.mode || "multiplayer";
    parent.dataset.fieldMode = FIELD.mode;
    parent.dataset.fieldW = String(FIELD.w);
    parent.dataset.ridge = String(data.ridge ?? 0);
    parent.dataset.craters = String(Array.isArray(data.craters) ? data.craters.length : 0);
    parent.dataset.debris = String([...(data.view && data.view.own || []), ...(data.view && data.view.reveal && data.view.reveal.bodies || [])].filter(body => String(body.role || "").startsWith("debris") && body.alive !== false).length);
    parent.dataset.botLevel = String(data.bot_level ?? "");
    const spot = (data.view && data.view.own || []).find(body => body.role === "launcher");
    if (spot) { parent.dataset.launcherX = String(spot.x); parent.dataset.launcherY = String(spot.y); }
    parent.dataset.turnNumber = String(data.turn ?? 0);
    parent.dataset.botThinking = data.bot_thinking ? "true" : "false";
    parent.dataset.botDueAt = String(data.bot_due_at ?? 0);
    parent.dataset.seat = data.seat || "";
    parent.dataset.phase = data.phase || "";
    parent.dataset.weapon = data.weapon || "";
    parent.dataset.reveal = data.view && data.view.reveal ? "open" : "closed";
    parent.dataset.powered = data.own_powered === false ? "false" : "true";
    parent.dataset.shotReady = data.shot_ready === false ? "false" : "true";
    parent.dataset.result = data.result || "";
    parent.dataset.enemyCores = data.enemy_cores === undefined ? "" : String(data.enemy_cores);
    parent.dataset.ownCore = data.own_core === false ? "false" : "true";
    parent.dataset.yourTurn = data.your_turn ? "true" : "false";
    parent.dataset.epoch = data.epoch === undefined ? "" : String(data.epoch);
    parent.dataset.revision = data.revision === undefined ? "" : String(data.revision);
    if (data.phase === "recon") {
        parent.dataset.broken = "false";
        parent.dataset.postAngle = typeof data.angle === "number" ? String(data.angle) : "0";
    } else if (typeof data.broken === "boolean") {
        parent.dataset.broken = data.broken ? "true" : "false";
        parent.dataset.postAngle = typeof data.angle === "number" ? String(data.angle) : "0";
    }
    const path = data.path || [];
    let maxX = 0;
    for (const point of path) {
        if (point[0] > maxX) {
            maxX = point[0];
        }
    }
    if (path.length) {
        parent.dataset.shotMaxX = String(maxX);
        parent.dataset.authoritative = "pymunk";
    } else if (Array.isArray(data.path)) {
        parent.dataset.shotScreenX = "";
        parent.dataset.shotTime = "";
    }
}

export function mountField(parent) {
    if (!parent) {
        return {
            destroy() {},
            apply() {},
        };
    }
    const handlers = ["pointerdown", "pointermove", "pointerup"];
    let pull = null;
    let sceneRef = null;
    let keyboardPull = null;
    let latest = null;
    let cancelGesture = () => {};
    parent.tabIndex = 0;
    const resetPullHint = () => {
        const hint = document.getElementById("fogshot-pull");
        if (hint) hint.textContent = parent.dataset.phase === "finished" ? "Duel finished. Rematch starts another duel."
            : parent.dataset.yourTurn === "true" ? (isLong() ? LONG_HELP : PULL_HELP) : "Wait for your turn.";
    };
    const game = new Game({
        type: AUTO,
        parent,
        width: VIEW_W,
        height: VIEW_H,
        backgroundColor: "#152e3a",
        scale: { mode: Scale.FIT, autoCenter: Scale.CENTER_BOTH, width: VIEW_W, height: VIEW_H },
        scene: {
            preload() {
                this.load.svg("night-ridge", new URL("../assets/night-ridge.svg?no-inline", import.meta.url).href, { width: VIEW_W, height: VIEW_H });
            },
            create() {
                this.sky = this.add.image(0, 0, "night-ridge").setOrigin(0).setScrollFactor(0);
                // Distant ridgelines scroll slowly on long fields (parallax); unused on the classic field.
                this.farPen = this.add.graphics().setScrollFactor(.25);
                this.landPen = this.add.graphics();
                this.rangeLabels = Array.from({ length: 8 }, () => this.add.text(0, 0, "", { fontFamily: "Arial", fontSize: "10px", color: "#9fc2b6", resolution: 2 }).setOrigin(.5, 0).setVisible(false));
                this.landKey = "";
                const fog = this.textures.createCanvas("fog-bank", VIEW_W, VIEW_H);
                const ctx = fog.context;
                const shade = ctx.createLinearGradient(320, 0, 580, 0);
                shade.addColorStop(0, "rgba(9,29,40,0)");
                shade.addColorStop(.45, "rgba(9,29,40,.7)");
                shade.addColorStop(1, "rgba(9,29,40,.92)");
                ctx.fillStyle = shade; ctx.fillRect(0, 0, VIEW_W, VIEW_H);
                for (let i = 0; i < 13; i++) {
                    ctx.fillStyle = "rgba(80,113,120,.012)";
                    ctx.beginPath(); ctx.ellipse(470 + (i * 83) % 350, 32 + i * 33, 70 + (i * 17) % 100, 10 + (i * 7) % 23, -.08, 0, Math.PI * 2); ctx.fill();
                }
                fog.refresh();
                this.fogBank = this.add.image(0, 0, "fog-bank").setOrigin(0);
                // Long fields: a soft fog edge at the midline and an even veil over the enemy half.
                // Light enough that the public terrain still reads under it.
                const edge = this.textures.createCanvas("fog-edge", 256, 4);
                const ectx = edge.context;
                const ramp = ectx.createLinearGradient(0, 0, 256, 0);
                ramp.addColorStop(0, "rgba(9,29,40,0)");
                ramp.addColorStop(1, "rgba(9,29,40,.6)");
                ectx.fillStyle = ramp; ectx.fillRect(0, 0, 256, 4);
                edge.refresh();
                this.fogEdge = this.add.image(0, 0, "fog-edge").setOrigin(0).setVisible(false);
                this.fogVeil = this.add.rectangle(0, 0, 10, 10, 0x091d28, .6).setOrigin(0).setVisible(false);
                // The public crest stays readable through the fog: you aim over those hills.
                this.crestPen = this.add.graphics();
                const wisp = this.textures.createCanvas("fog-wisp", 320, 110);
                const wctx = wisp.context;
                // Soft blurred ellipses; the padding keeps the blur from clipping into hard edges.
                wctx.filter = "blur(14px)";
                wctx.fillStyle = "rgba(150,182,178,.42)";
                wctx.beginPath(); wctx.ellipse(160, 58, 112, 17, 0, 0, Math.PI * 2); wctx.fill();
                wctx.fillStyle = "rgba(170,198,190,.3)";
                wctx.beginPath(); wctx.ellipse(120, 50, 60, 11, -.06, 0, Math.PI * 2); wctx.fill();
                wisp.refresh();
                this.wisps = [[540, 120, .23, 40, .38], [660, 215, .17, 55, .46], [500, 300, .29, 35, .4], [700, 345, .21, 45, .34]].map(([x, y, speed, amp, alpha], i) => ({
                    image: this.add.image(x, y, "fog-wisp").setAlpha(alpha), baseX: x, baseY: y, speed, amp, alpha, phase: i * 1.9,
                }));
                this.fogPen = this.add.graphics();
                this.fxPen = this.add.graphics();
                this.hudPen = this.add.graphics().setScrollFactor(0).setDepth(20);
                this.landedAt = null; this.landPoint = null; this.lookAt = null; this.lockedPull = null;
                this.aimDrag = null; this.panDrag = null; this.stripDrag = null; this.strip = null;
                this.shards = []; this.flashes = []; this.trail = []; this.banner = null; this.bannerKey = "";
                this.heading = null; this.landed = false; this.recoil = null; this.activePull = null; this.coach = true;
                const bannerFont = { fontFamily: "Inter, 'Segoe UI', Arial, sans-serif", fontStyle: "bold", resolution: 2, align: "center" };
                this.bannerTitle = this.add.text(VIEW_W / 2, 90, "", { ...bannerFont, fontSize: "30px", color: "#f4d58f" }).setOrigin(.5).setVisible(false);
                this.bannerTitle.setLetterSpacing && this.bannerTitle.setLetterSpacing(4);
                this.bannerSub = this.add.text(VIEW_W / 2, 120, "", { ...bannerFont, fontStyle: "normal", fontSize: "11px", color: "#c9d8cf" }).setOrigin(.5).setVisible(false);
                this.bannerTitle.setScrollFactor(0).setDepth(21);
                this.bannerSub.setScrollFactor(0).setDepth(21);
                this.aimLabel = this.add.text(0, 0, "", { ...bannerFont, fontSize: "10px", color: "#f1d18b", backgroundColor: "#0c222bcc", padding: { x: 5, y: 2 } }).setOrigin(.5).setVisible(false);
                this.coachLabel = this.add.text(0, 0, "DRAG BACK", { ...bannerFont, fontSize: "9px", color: "#f1d18b" }).setOrigin(.5).setVisible(false);
                const labelStyle = { fontFamily: "Arial", fontSize: "9px", color: "#b8d6c6", backgroundColor: "#102a34", padding: { x: 5, y: 3 }, resolution: 2 };
                this.coreLabel = this.add.text(0, 0, "", labelStyle).setOrigin(.5);
                this.launchLabel = this.add.text(0, 0, "", { ...labelStyle, fontSize: "8px", color: "#dfd6ac" }).setOrigin(.5);
                this.fieldParent = parent;
                const resizeLabels = () => {
                    const size = Math.max(9, 10 / Math.max(.2, parent.clientWidth / VIEW_W));
                    this.coreLabel.setFontSize(size);
                    this.launchLabel.setFontSize(size);
                    this.coachLabel.setFontSize(Math.round(9 * uiScale(this)));
                    if (this.view) paint(this, pull);
                };
                this.scale.on("resize", resizeLabels);
                resizeLabels();
                this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
                this.yourTurn = false;
                this.reveal = null;
                this.weapon = "flare";
                sceneRef = this;
                this.shot = null;
                this.view = null;
                this.seat = "";
                this.powered = true;
                this.path = null;
                this.pathStart = null;
                this.collapse = null;
                this.collapseAngle = null;
                this.collapseId = "";
                this.epoch = 0;
                this.revision = 0;
                this.input.addPointer(2);
                let activeId = null;
                let contaminated = false;
                cancelGesture = () => {
                    pull = null; keyboardPull = null; activeId = null; contaminated = false;
                    this.aimDrag = null; this.panDrag = null; this.stripDrag = null;
                    parent.dataset.cancelled = "true";
                    resetPullHint();
                    paint(this, null);
                };
                const finishPull = (pointer, outside) => {
                    if (!pull || pointer.id !== activeId) {
                        return;
                    }
                    const release = { x: pointer.x, y: pointer.y };
                    const yourTurn = Boolean(parent && parent.dataset.yourTurn === "true");
                    const allowed = releaseAllowed({
                        yourTurn,
                        outside,
                        extraPointer: contaminated,
                        cancelled: outside || Boolean(pointer.wasCanceled),
                    });
                    pull = null;
                    activeId = null;
                    contaminated = false;
                    resetPullHint();
                    paint(this, null);
                    if (!allowed) {
                        if (parent) {
                            parent.dataset.cancelled = "true";
                        }
                        return;
                    }
                    if (parent) {
                        parent.dataset.cancelled = "false";
                        parent.dataset.pulls = String(Number(parent.dataset.pulls || 0) + 1);
                        parent.dataset.releaseX = String(release.x);
                        parent.dataset.releaseY = String(release.y);
                    }
                    const fire = window.fogshotFire;
                    if (fire) {
                        const protocol = protocolPull(this.seat, release);
                        fire(protocol.x, protocol.y);
                    }
                };
                paint(this, null);
                // ---- long range input: drag anywhere to aim (relative), release to set, FIRE to launch.
                // Off-turn drags pan the camera; the minimap strip looks wherever you touch it.
                const onStrip = (pointer) => {
                    const strip = this.strip;
                    return Boolean(strip) && pointer.x >= strip.x - 6 && pointer.x <= strip.x + strip.w + 6 && pointer.y >= strip.y - 8 && pointer.y <= strip.y + strip.h + 8;
                };
                const lookStrip = (pointer) => {
                    const world = fieldPixels(FIELD);
                    const x = overviewToWorld(pointer.x, this.strip, world);
                    this.lookAt = { x, y: groundScreenY(this.terrain, x) - 140 };
                    const cam = this.cameras.main;
                    const at = cameraOn(this.lookAt, VIEW, world);
                    cam.setScroll(at.x, at.y);
                };
                const longDown = (pointer) => {
                    if (this.aimDrag || this.panDrag || this.stripDrag) {
                        if (this.aimDrag) { contaminated = true; parent.dataset.extraPointer = "true"; }
                        return;
                    }
                    if (onStrip(pointer)) { this.stripDrag = pointer.id; lookStrip(pointer); return; }
                    if (parent.dataset.yourTurn === "true" && parent.dataset.phase !== "finished") {
                        keyboardPull = null;
                        this.lookAt = null;
                        this.coach = false;
                        dismissBanner(this);
                        this.aimDrag = { id: pointer.id, start: { x: pointer.x, y: pointer.y }, base: this.lockedPull };
                        activeId = pointer.id;
                        pull = dragPull(this.seat, this.aimDrag.base, this.aimDrag.start, pointer);
                        paint(this, pull);
                        return;
                    }
                    const cam = this.cameras.main;
                    this.panDrag = { id: pointer.id, start: { x: pointer.x, y: pointer.y }, scroll: { x: cam.scrollX, y: cam.scrollY } };
                };
                const longMove = (pointer) => {
                    if (this.stripDrag === pointer.id) { lookStrip(pointer); return; }
                    if (this.panDrag && this.panDrag.id === pointer.id) {
                        const cam = this.cameras.main;
                        const at = clampScroll({ x: this.panDrag.scroll.x + this.panDrag.start.x - pointer.x, y: this.panDrag.scroll.y + this.panDrag.start.y - pointer.y }, VIEW, fieldPixels(FIELD));
                        cam.setScroll(at.x, at.y);
                        this.lookAt = { x: at.x + VIEW.w / 2, y: at.y + VIEW.h / 2 };
                        return;
                    }
                    if (this.aimDrag && this.aimDrag.id === pointer.id) {
                        pull = dragPull(this.seat, this.aimDrag.base, this.aimDrag.start, pointer);
                        parent.dataset.pointerX = String(pointer.x);
                        parent.dataset.pointerY = String(pointer.y);
                        paint(this, pull);
                    }
                };
                const longUp = (pointer) => {
                    if (this.stripDrag === pointer.id) { this.stripDrag = null; return; }
                    if (this.panDrag && this.panDrag.id === pointer.id) { this.panDrag = null; return; }
                    if (!this.aimDrag || this.aimDrag.id !== pointer.id) return;
                    const candidate = dragPull(this.seat, this.aimDrag.base, this.aimDrag.start, pointer);
                    const spoiled = contaminated || Boolean(pointer.wasCanceled);
                    this.aimDrag = null; activeId = null; contaminated = false; pull = null;
                    if (!spoiled && longAim(this.seat, candidate, FIELD).valid) setLocked(candidate);
                    else parent.dataset.cancelled = "true";
                    paint(this, null);
                };
                this.longInput = { down: longDown, move: longMove, up: longUp };
                if (latest) applyData(latest);
                this.input.on(handlers[0], (pointer) => {
                    if (isLong()) { longDown(pointer); return; }
                    if (pull && !keyboardPull) {
                        contaminated = true;
                        if (parent) {
                            parent.dataset.extraPointer = "true";
                        }
                        return;
                    }
                    if (parent.dataset.yourTurn !== "true") return;
                    keyboardPull = null;
                    resetPullHint();
                    activeId = pointer.id;
                    pull = { x: pointer.x, y: pointer.y };
                    this.coach = false;
                    dismissBanner(this);
                    paint(this, pull);
                });
                this.input.on(handlers[1], (pointer) => {
                    if (isLong()) { longMove(pointer); return; }
                    if (!pull || pointer.id !== activeId) {
                        return;
                    }
                    pull = { x: pointer.x, y: pointer.y };
                    if (parent) {
                        parent.dataset.pointerX = String(pointer.x);
                        parent.dataset.pointerY = String(pointer.y);
                    }
                    paint(this, pull);
                });
                this.input.on(handlers[2], (pointer) => {
                    if (isLong()) { longUp(pointer); return; }
                    const outside = pointer.x < 0 || pointer.y < 0 || pointer.x > VIEW_W || pointer.y > VIEW_H;
                    finishPull(pointer, outside);
                });
                this.input.on("pointerupoutside", (pointer) => {
                    if (isLong()) { longUp(pointer); return; }
                    finishPull(pointer, true);
                });
            },
            update(time, delta) {
                // Frame-rate readout for QA (once a second, no layout cost).
                if (!this.fpsAt || time - this.fpsAt > 1000) { this.fpsAt = time; parent.dataset.fps = String(Math.round(this.game.loop.actualFps)); }
                animate(this, time, delta);
                if (isLong()) steerCamera(this, time, delta);
                const path = this.path;
                if (!path || !path.length) {
                    if (this.effectLive) paint(this, pull);
                    if (this.shot || this.collapseAngle !== null) {
                        this.shot = null;
                        this.collapseAngle = null;
                        if (parent) {
                            parent.dataset.shotScreenX = "";
                            parent.dataset.shotTime = "";
                        }
                        paint(this, pull);
                    }
                    return;
                }
                if (this.pathStart === null) {
                    this.pathStart = time;
                }
                // Long flights replay faster so a 6 s arc does not drag.
                const elapsed = (time - this.pathStart) / 1000 * (isLong() ? PLAY_RATE_LONG : 1);
                const point = sampleAt(path, elapsed, 2, false);
                const last = path[path.length - 1];
                if (!this.landed && point && elapsed >= (last.length > 2 ? last[2] : 0)) {
                    // The server path ended: land it with an impact instead of parking the shell.
                    this.landed = true;
                    this.landedAt = time;
                    this.landPoint = worldToScreen(last[0], last[1]);
                    impact(this, this.landPoint, this.pathWeapon || this.weapon, this.heading);
                }
                if (point) {
                    const next = worldToScreen(point[0], point[1]);
                    const heading = headingOf(this.shot, next);
                    if (heading !== null) this.heading = heading;
                    if (!this.landed && (!this.trail.length || headingOf(this.trail[this.trail.length - 1], next, 1.5) !== null)) {
                        this.trail.push(next);
                        if (this.trail.length > 16) this.trail.shift();
                    }
                    this.shot = next;
                    if (parent) {
                        parent.dataset.shotScreenX = String(this.shot.x);
                        parent.dataset.shotTime = String(point[2]);
                    }
                } else {
                    this.shot = null;
                    if (parent) {
                        parent.dataset.shotScreenX = "";
                        parent.dataset.shotTime = "";
                    }
                }
                const falling = sampleAt(this.collapse, elapsed, 1, true);
                if (falling) {
                    this.collapseAngle = falling[0];
                }
                paint(this, pull);
            },
        },
    });
    // Phaser re-reads the canvas position only every 500 ms, so a layout shift above the field (a
    // label wrapping on a phone) could offset the first touch of a drag. Refresh it before Phaser
    // sees the press (capture phase on the parent runs before the canvas listeners).
    const freshBounds = () => { if (game.scale) game.scale.updateBounds(); };
    for (const type of ["pointerdown", "touchstart", "mousedown"]) parent.addEventListener(type, freshBounds, { capture: true, passive: true });
    // ---- long range aim: a locked aim survives between turns so you can correct from the last shot.
    const aimBar = document.getElementById("fogshot-aimbar");
    const readout = () => {
        const out = document.getElementById("fogshot-aimread");
        const fireButton = document.getElementById("fogshot-fire");
        const locked = sceneRef && sceneRef.lockedPull ? longAim(sceneRef.seat, sceneRef.lockedPull, FIELD) : null;
        const ready = Boolean(locked && locked.valid && parent.dataset.yourTurn === "true" && parent.dataset.phase !== "finished");
        if (out) out.textContent = locked ? `${locked.degrees.toFixed(1)}° · ${(locked.fraction * 100).toFixed(1)}% · ${locked.power.toFixed(1)} m/s` : "Drag the field to aim";
        if (fireButton) { fireButton.disabled = !ready; fireButton.classList.toggle("is-ready", ready); }
        parent.dataset.aimLocked = locked && locked.valid ? "true" : "false";
        if (locked) { parent.dataset.aimDegrees = locked.degrees.toFixed(2); parent.dataset.aimPercent = (locked.fraction * 100).toFixed(2); }
    };
    const setLocked = (padPull) => {
        if (!sceneRef) return;
        sceneRef.lockedPull = padPull ? { x: padPull.x, y: padPull.y } : null;
        readout();
        paint(sceneRef, pull);
    };
    const fireLong = () => {
        if (!sceneRef || parent.dataset.yourTurn !== "true" || parent.dataset.phase === "finished" || !sceneRef.lockedPull) return;
        const aim = longAim(sceneRef.seat, sceneRef.lockedPull, FIELD);
        if (!aim.valid || !window.fogshotFire) return;
        parent.dataset.cancelled = "false";
        parent.dataset.pulls = String(Number(parent.dataset.pulls || 0) + 1);
        parent.dataset.releaseX = String(aim.pointer.x);
        parent.dataset.releaseY = String(aim.pointer.y);
        sceneRef.lookAt = null;
        window.fogshotFire(aim.pointer.x, aim.pointer.y);
    };
    const nudge = (kind, amount) => {
        if (!sceneRef || parent.dataset.yourTurn !== "true") return;
        const base = sceneRef.lockedPull || padFromAim(Math.PI / 4, .7, FIELD);
        let padAngle = Math.atan2(base.y, base.x);
        let fraction = Math.min(1, Math.hypot(base.x, base.y) / FIELD.full_pull);
        if (kind === "angle") padAngle = Math.max(-19 * Math.PI / 180, Math.min(75 * Math.PI / 180, padAngle + amount * Math.PI / 180));
        else fraction = Math.max(.06, Math.min(1, fraction + amount / 100));
        sceneRef.coach = false;
        dismissBanner(sceneRef);
        sceneRef.lookAt = null;
        setLocked(padFromAim(padAngle, fraction, FIELD));
    };
    const onBar = (event) => {
        const button = event.target && event.target.closest ? event.target.closest("[data-aim]") : null;
        if (!button || !sceneRef) return;
        const act = button.dataset.aim;
        const world = fieldPixels(FIELD);
        const cam = sceneRef.cameras.main;
        const facing = sceneRef.seat === "B" ? -1 : 1;
        if (act === "fire") fireLong();
        else if (act === "home") sceneRef.lookAt = null;
        else if (act === "look-ahead" || act === "look-back") {
            const step = (act === "look-ahead" ? 1 : -1) * facing * VIEW.w * .75;
            const x = Math.max(0, Math.min(world.w, cam.scrollX + VIEW.w / 2 + step));
            sceneRef.lookAt = { x, y: groundScreenY(sceneRef.terrain, x) - 140 };
        }
        else if (act === "angle-up") nudge("angle", .5);
        else if (act === "angle-down") nudge("angle", -.5);
        else if (act === "power-up") nudge("power", .5);
        else if (act === "power-down") nudge("power", -.5);
    };
    if (aimBar) aimBar.addEventListener("click", onBar);
    const onLongKey = (event) => {
        if (!["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Enter", " ", "Escape", "h", "H"].includes(event.key)) return false;
        event.preventDefault();
        if (!sceneRef) return true;
        if (event.key === "h" || event.key === "H") { sceneRef.lookAt = null; return true; }
        if (parent.dataset.yourTurn !== "true") return true;
        const big = event.shiftKey ? 4 : 1;
        if (event.key === "Escape") { cancelGesture(); setLocked(null); }
        else if (event.key === "Enter" || event.key === " ") { if (!event.repeat) fireLong(); }
        else if (event.key === "ArrowUp") nudge("angle", .5 * big);
        else if (event.key === "ArrowDown") nudge("angle", -.5 * big);
        else if (event.key === "ArrowRight") nudge("power", .5 * big);
        else if (event.key === "ArrowLeft") nudge("power", -.5 * big);
        return true;
    };
    const onKey = (event) => {
        if (isLong()) { onLongKey(event); return; }
        if (!["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Enter", "Escape"].includes(event.key)) return;
        event.preventDefault();
        if (!sceneRef || parent.dataset.yourTurn !== "true") return;
        if (event.key === "Escape") { cancelGesture(); return; }
        if (event.key === "Enter") {
            if (keyboardPull && !event.repeat && window.fogshotFire) {
                const protocol = protocolPull(sceneRef.seat, keyboardPull);
                window.fogshotFire(protocol.x, protocol.y);
                pull = null; keyboardPull = null; resetPullHint(); paint(sceneRef, null);
            }
            return;
        }
        if (!keyboardPull) cancelGesture();
        sceneRef.coach = false;
        dismissBanner(sceneRef);
        keyboardPull ||= { x: sceneRef.seat === "B" ? 780 : 20, y: 340 };
        if (event.key === "ArrowLeft") keyboardPull.x = Math.max(0, keyboardPull.x - 4);
        if (event.key === "ArrowRight") keyboardPull.x = Math.min(799, keyboardPull.x + 4);
        if (event.key === "ArrowUp") keyboardPull.y = Math.max(0, keyboardPull.y - 4);
        if (event.key === "ArrowDown") keyboardPull.y = Math.min(399, keyboardPull.y + 4);
        pull = { ...keyboardPull };
        paint(sceneRef, pull);
        const aim = pullFeedback(sceneRef.seat, pull, launcherWorld(sceneRef));
        const hint = document.getElementById("fogshot-pull");
        if (hint) hint.textContent = aim.valid ? `Pull ${Math.round(aim.pullFraction * 100)}%. Enter to launch, Escape to cancel.` : "Adjust the pull behind the launcher.";
    };
    parent.addEventListener("keydown", onKey);
    const onRematchKey = (event) => {
        if (event.repeat || event.ctrlKey || event.metaKey || event.altKey || (event.key !== "r" && event.key !== "R")) return;
        const target = event.target;
        if (target && (target.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName))) return;
        const rematch = document.getElementById("fogshot-rematch");
        if (parent.dataset.phase === "finished" && rematch && !rematch.disabled) { event.preventDefault(); rematch.click(); }
    };
    window.addEventListener("keydown", onRematchKey);
    saveRecord(loadRecord() || {});
    const onBlur = () => cancelGesture();
    window.addEventListener("blur", onBlur);
    const onVisible = () => { if (!document.hidden && sceneRef) paint(sceneRef, pull); };
    document.addEventListener("visibilitychange", onVisible);
    parent.dataset.fogshotHandlers = String(handlers.length);
    parent.dataset.reveal = "closed";
    return {
        destroy() {
            parent.removeEventListener("keydown", onKey);
            for (const type of ["pointerdown", "touchstart", "mousedown"]) parent.removeEventListener(type, freshBounds, { capture: true });
            if (aimBar) aimBar.removeEventListener("click", onBar);
            window.removeEventListener("keydown", onRematchKey);
            window.removeEventListener("blur", onBlur);
            document.removeEventListener("visibilitychange", onVisible);
            if (sceneRef && sceneRef.revealTimer) clearTimeout(sceneRef.revealTimer);
            game.destroy(true);
        },
        apply: applyData,
    };

    function applyData(raw) {
            if (!sceneRef) {
                latest = raw;
                return;
            }
            let data = raw;
            if (typeof raw === "string") {
                try {
                    data = JSON.parse(raw);
                } catch (err) {
                    return;
                }
            }
            if (!data || typeof data !== "object") {
                return;
            }
            if (isStale(sceneRef, data)) {
                return;
            }
            const observedAt = Date.now();
            data = observationAt(data, observedAt);
            const nextField = fieldOf(data);
            if (nextField.mode !== FIELD.mode || nextField.w !== FIELD.w || nextField.h !== FIELD.h) {
                FIELD = nextField;
                const px = fieldPixels(FIELD);
                sceneRef.cameras.main.setBounds(0, 0, px.w, px.h);
                if (!isLong()) sceneRef.cameras.main.setScroll(0, 0);
                sceneRef.snapCamera = true;
                sceneRef.landKey = "";
                sceneRef.lockedPull = null;
            }
            const nextEpoch = data.epoch === undefined ? sceneRef.epoch : data.epoch;
            const epochChanged = nextEpoch !== sceneRef.epoch;
            if (epochChanged) {
                sceneRef.lockedPull = null; sceneRef.lookAt = null; sceneRef.landedAt = null; sceneRef.snapCamera = true;
                sceneRef.path = null;
                sceneRef.collapse = null;
                sceneRef.collapseAngle = null;
                sceneRef.collapseId = "";
                sceneRef.shot = null;
                sceneRef.pathStart = null;
            }
            sceneRef.epoch = nextEpoch;
            if (data.revision !== undefined) {
                sceneRef.revision = data.revision;
            }
            if (epochChanged || (sceneRef.yourTurn && !data.your_turn)) cancelGesture();
            if (!sceneRef.yourTurn && data.your_turn && !(sceneRef.shot && !sceneRef.landed)) sceneRef.lookAt = null;
            const before = sceneRef.lastData;
            sceneRef.lastData = data;
            if (epochChanged) { sceneRef.shards = []; sceneRef.flashes = []; sceneRef.trail = []; sceneRef.landed = false; sceneRef.banner = null; sceneRef.bannerKey = ""; sceneRef.bannerTitle.setVisible(false); sceneRef.bannerSub.setVisible(false); }
            if (data.phase === "recon" && Number(data.turn || 0) === 0 && data.your_turn) sceneRef.coach = sceneRef.coach || epochChanged;
            else sceneRef.coach = false;
            const sameDuel = before && !epochChanged && before.epoch === data.epoch;
            if (sameDuel && before.own_core !== false && data.own_core === false) {
                const core = (data.view && data.view.own || []).find(body => body.role === "core");
                if (core) {
                    const at = worldToScreen(core.x, core.y);
                    spawn(sceneRef, burst(at.x, at.y, { count: 34, speed: 210, life: 1.1, size: 5 }), [0xf0cb7b, 0xf0a48a, 0x8fc5b6, 0xfff3d4]);
                    flash(sceneRef, at.x, at.y, 0xf0a48a, 60, .7);
                }
                shake(sceneRef, 260, .009);
            }
            if (sameDuel && Number(before.enemy_cores) > Number(data.enemy_cores)) {
                const at = data.reveal_radius > 0 ? worldToScreen(data.reveal_x, data.reveal_y) : { x: VIEW_W * .25, y: VIEW_H * .7 };
                spawn(sceneRef, burst(at.x, at.y, { count: 30, speed: 200, life: 1.1, size: 5 }), [0xf2cb78, 0xe5b56c, 0xfff3d4]);
                flash(sceneRef, at.x, at.y, 0xf2cb78, 60, .7);
                shake(sceneRef, 220, .007);
            }
            const banner = bannerFor(data);
            const bannerKey = banner ? `${data.epoch}:${banner.kind === "turn" ? data.turn : "end"}:${banner.kind}` : "";
            if (banner && bannerKey !== sceneRef.bannerKey) {
                showBanner(sceneRef, banner, bannerKey);
                if (banner.kind === "victory" && sameDuel && before.phase !== "finished" && !sceneRef.reducedMotion) {
                    // Triangle confetti cascading from the top edge.
                    const cam = sceneRef.cameras.main;
                    for (let i = 0; i < 5; i++) spawn(sceneRef, burst(cam.scrollX + VIEW_W * (.15 + i * .175), cam.scrollY - 6, { count: 10, speed: 90, heading: Math.PI / 2, spread: 1.6, life: 2.2, size: 4 }), [0xf4d58f, 0x8fc5b6, 0xe5b56c, 0xf0e9c8]);
                }
            } else if (!banner) dismissBanner(sceneRef);
            if (data.result && data.seat) saveRecord(recordAfter(loadRecord(), data, `${data.room || parent.dataset.room || ""}:${data.epoch}`));
            sceneRef.view = data.view || sceneRef.view;
            sceneRef.yourTurn = Boolean(data.your_turn);
            sceneRef.weapon = data.weapon || sceneRef.weapon;
            if (sceneRef.revealTimer) { clearTimeout(sceneRef.revealTimer); sceneRef.revealTimer = null; }
            if (data.view && data.view.reveal && data.reveal_radius > 0 && data.reveal_until > observedAt) {
                const key = `${data.epoch}:${data.reveal_until}`;
                if (!sceneRef.reveal || sceneRef.reveal.key !== key) {
                    sceneRef.reveal = { key, x: data.reveal_x, y: data.reveal_y, radius: data.reveal_radius, until: data.reveal_until, started: sceneRef.time.now };
                }
                // Expire locally even if the next poll fails. No enemy art persists.
                sceneRef.revealTimer = setTimeout(() => {
                    expireObservation(sceneRef);
                    paint(sceneRef, pull);
                }, Math.max(0, data.reveal_until - Date.now()));
            } else {
                sceneRef.reveal = null;
                if (sceneRef.view) sceneRef.view = { ...sceneRef.view, reveal: null };
            }
            if (data.seat) {
                sceneRef.seat = data.seat;
            }
            if (typeof data.own_powered === "boolean") {
                sceneRef.powered = data.own_powered;
            }
            const now = sceneRef.time ? sceneRef.time.now : 0;
            const elapsed = sceneRef.pathStart === null ? 0 : (now - sceneRef.pathStart) / 1000 * (isLong() ? PLAY_RATE_LONG : 1);
            const frame = stepWatch({
                path: sceneRef.path,
                collapse: sceneRef.collapse,
                collapseId: sceneRef.collapseId,
                broken: parent.dataset.broken === "true",
                angle: Number(parent.dataset.postAngle || 0),
            }, data, elapsed);
            if (frame.path !== sceneRef.path) {
                sceneRef.pathStart = frame.path ? now : null;
                sceneRef.trail = []; sceneRef.landed = false; sceneRef.heading = null; sceneRef.shot = null;
                sceneRef.landedAt = null; sceneRef.lookAt = null;
                sceneRef.pathWeapon = data.weapon || sceneRef.weapon;
                if (frame.path && frame.path.length) {
                    const origin = worldToScreen(frame.path[0][0], frame.path[0][1]);
                    const launch = launcherOf(sceneRef);
                    if (Math.hypot(origin.x - launch.x, origin.y - launch.y) < 60) {
                        sceneRef.recoil = now;
                        const second = frame.path[Math.min(frame.path.length - 1, 3)];
                        const toward = headingOf(origin, worldToScreen(second[0], second[1]), .01);
                        spawn(sceneRef, burst(launch.x, launch.y, { count: 9, speed: 90, life: .45, size: 3, heading: toward === null ? -Math.PI / 4 : toward, spread: 1.1 }), [0xf1d18b, 0xd8c48b, 0xfff3d4]);
                    }
                }
            }
            sceneRef.path = frame.path;
            sceneRef.collapse = frame.collapse;
            sceneRef.collapseId = frame.collapseId;
            sceneRef.collapseAngle = frame.collapseAngle;
            sceneRef.shot = frame.shot ? worldToScreen(frame.shot[0], frame.shot[1]) : null;
            if (!frame.shot && parent) {
                parent.dataset.shotScreenX = "";
                parent.dataset.shotTime = "";
            }
            remember(parent, data);
            if (Array.isArray(data.terrain) && !(Array.isArray(data.craters) && data.craters.length)) sceneRef.terrain = data.terrain;
            paintLand(sceneRef, data);
            paint(sceneRef, pull);
            readout();
    }
}
