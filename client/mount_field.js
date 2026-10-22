// Phaser 3.90 scene mount. Jac lambdas do not bind Phaser's scene `this`,
// so the create/input callbacks live in this adapter. The projectile path,
// post pose, and reveal bodies come from the server payload. This file does
// not integrate a shot or decide a hit.
import { AUTO, Game, Scale } from "phaser";
import "../assets/field.css";
import { bodySize, pullFeedback, hudState, protocolPull, observationAt, trianglePoints, headingOf, easeOutBack, easeOutCubic, burst, stepShards, bannerFor, recordAfter, recordLabel } from "./presentation.js";
import { isStale, releaseAllowed, sampleAt, stepWatch } from "./playback.js";

const ARENA_W = 40;
const ARENA_H = 16;
const VIEW_W = 800;
const VIEW_H = 400;
const PULL_HELP = "Drag back and release. Keyboard: Tab to field, arrows aim, Enter fires, Escape cancels.";
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
    // Sine-drifting fog wisps over the hidden half (mirrored for seat B).
    if (scene.wisps) {
        const flip = scene.seat === "B";
        scene.wisps.forEach((wisp, i) => {
            const drift = scene.reducedMotion ? 0 : Math.sin(t * wisp.speed + wisp.phase) * wisp.amp;
            const x = wisp.baseX + drift;
            wisp.image.setPosition(flip ? VIEW_W - x : x, wisp.baseY + (scene.reducedMotion ? 0 : Math.sin(t * wisp.speed * 1.7 + i) * 4));
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
    if (pull) {
        const aim = pullFeedback(scene.seat, pull);
        const heading = -aim.angle; // world y-up angle -> screen y-down angle
        const color = aim.valid ? 0xf1d18b : 0xb98472;
        aim.guide.forEach((point, n) => {
            const wave = scene.reducedMotion ? .6 : .5 + .5 * Math.sin(t * 9 - n * .9);
            const [a, b, c] = trianglePoints(point.x, point.y, 2.6 + wave * 1.6 + aim.pullFraction * 1.2, heading);
            fx.fillStyle(color, .45 + .55 * wave); fx.fillTriangle(a.x, a.y, b.x, b.y, c.x, c.y);
        });
        const pct = Math.round(aim.pullFraction * 100);
        const degrees = Math.round(aim.angle * 180 / Math.PI);
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
            fx.fillStyle(0x081a22, .72 * alpha);
            fx.fillRoundedRect(VIEW_W / 2 - w / 2, y - scene.bannerTitle.displayHeight / 2 - 9, w, h, 8);
            const edge = banner.kind === "defeat" ? 0xf0a48a : banner.kind === "victory" ? 0xf4d58f : 0x8fc5b6;
            fx.lineStyle(1, edge, .6 * alpha);
            fx.strokeRoundedRect(VIEW_W / 2 - w / 2, y - scene.bannerTitle.displayHeight / 2 - 9, w, h, 8);
            if (banner.persistent && !scene.reducedMotion) {
                // Slow rotating triangle crest on either side of the result.
                for (const side of [-1, 1]) {
                    const cx = VIEW_W / 2 + side * (w / 2 + 18), spin = t * 1.2 * side;
                    const [a, b, c] = trianglePoints(cx, y, 9, spin);
                    fx.lineStyle(1.5, edge, .8 * alpha); fx.strokeTriangle(a.x, a.y, b.x, b.y, c.x, c.y);
                }
            }
        }
    }
}

function worldToScreen(x, y) {
    return {
        x: (x / ARENA_W) * VIEW_W,
        y: (1 - y / ARENA_H) * VIEW_H,
    };
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

function drawBodies(pen, bodies, friendly, scene) {
    for (const body of bodies) {
        if (["ground", "marker", "launcher"].includes(body.role)) continue;
        const center = worldToScreen(body.x, body.y);
        if (center.x < -40 || center.x > VIEW_W + 40) continue;
        const { width, height } = bodySize(body);
        if (!width || !height) continue;
        const falling = body.role === "post" && scene.collapseId === body.id && typeof scene.collapseAngle === "number";
        pen.save();
        pen.translateCanvas(center.x, center.y);
        pen.rotateCanvas(-(falling ? scene.collapseAngle : body.angle));
        const edge = friendly ? 0x8fc5b6 : 0xe5b56c;
        const dark = body.alive === false ? 0x39494a : friendly ? 0x355d63 : 0x7e694b;
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
        } else if (height > 12 && width > 4) {
            pen.lineStyle(1, edge, .65);
            for (let y = -height / 2 + 7; y < height / 2 - 6; y += 12) {
                pen.lineBetween(-width / 2 + inset, y, width / 2 - inset, y + 6);
            }
        }
        pen.restore();
    }
}

function launcherOf(scene) {
    for (const body of ownBodies(scene.view)) {
        if (body.role === "launcher") return worldToScreen(body.x, body.y);
    }
    return worldToScreen(scene.seat === "B" ? 34 : 6, 4);
}

function drawLauncher(pen, scene, pull) {
    const launch = launcherOf(scene);
    scene.launch = launch;
    const direction = scene.seat === "B" ? -1 : 1;
    // Indestructible launch utility; its decorative pedestal is not a target.
    pen.fillStyle(0x0c2730, 1);
    pen.fillRect(launch.x - 19, launch.y + 29, 38, 68);
    pen.lineStyle(2, 0x456d71, 1);
    pen.lineBetween(launch.x - 15, launch.y + 93, launch.x + 15, launch.y + 32);
    pen.lineBetween(launch.x + 15, launch.y + 93, launch.x - 15, launch.y + 32);
    pen.fillStyle(0x244751, 1);
    pen.fillRoundedRect(launch.x - 30, launch.y + 23, 60, 12, 3);
    pen.fillStyle(0x83b8a9, 1);
    pen.fillRect(launch.x - 30, launch.y + 23, 60, 3);
    pen.lineStyle(6, 0x416870, 1);
    pen.lineBetween(launch.x - 13, launch.y + 23, launch.x - 8, launch.y - 10);
    pen.lineBetween(launch.x + 13, launch.y + 23, launch.x + 8, launch.y - 10);
    pen.lineStyle(2, 0xd8c48b, 1);
    const aim = pull ? pullFeedback(scene.seat, pull) : null;
    const pouch = pull ? { x: launch.x - Math.cos(aim.angle) * Math.min(30, aim.power * 4), y: launch.y + Math.sin(aim.angle) * Math.min(30, aim.power * 4) } : launch;
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
    scene.launchLabel.setText(phase === "finished" ? "DUEL OVER" : scene.yourTurn ? "PULL TO FIRE" : botThinking ? "BOT AIMING" : "STAND BY");
    scene.activePull = pull || null;
}

function renderHud(data) {
    const status = hudState(data);
    const put = (id, text) => { const element = document.getElementById(id); if (element && element.textContent !== text) element.textContent = text; };
    const rematch = document.getElementById("fogshot-rematch");
    if (rematch) { rematch.disabled = data.phase !== "finished"; rematch.title = data.phase === "finished" ? "Play another duel (R)" : "Available after the duel"; rematch.classList.toggle("is-ready", data.phase === "finished"); }
    put("fogshot-room", data.mode === "practice" ? "Practice bot" : data.room || "------");
    put("fogshot-turn", status.turn);
    put("fogshot-weapon", status.weapon);
    put("fogshot-supply", status.supply);
    put("fogshot-cores", `Own: ${status.core}\nEnemy: ${status.enemy}`);
    put("fogshot-observation", data.view && data.view.reveal ? "OBSERVATION OPEN / REMEMBER THIS" : "ENEMY STRUCTURES HIDDEN");
    const field = document.getElementById("fogshot-field");
    if (!data.your_turn) put("fogshot-pull", status.turn + (data.phase === "finished" ? ". Rematch starts another duel." : ". Wait for your turn."));
    else if (field?.dataset.yourTurn !== "true" || field?.dataset.epoch !== String(data.epoch)) put("fogshot-pull", PULL_HELP);
}

export function practiceFromLocation() {
    return new URLSearchParams(window.location.search).get("practice") === "1";
}

export function cancelField() {
    window.dispatchEvent(new Event("blur"));
    const button = document.getElementById("fogshot-rematch");
    if (button) button.disabled = true;
}

export function navigateMode(practice) {
    const url = new URL(window.location.href);
    url.search = "";
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
            : parent.dataset.yourTurn === "true" ? PULL_HELP : "Wait for your turn.";
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
                this.add.image(0, 0, "night-ridge").setOrigin(0);
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
                this.shards = []; this.flashes = []; this.trail = []; this.banner = null; this.bannerKey = "";
                this.heading = null; this.landed = false; this.recoil = null; this.activePull = null; this.coach = true;
                const bannerFont = { fontFamily: "Inter, 'Segoe UI', Arial, sans-serif", fontStyle: "bold", resolution: 2, align: "center" };
                this.bannerTitle = this.add.text(VIEW_W / 2, 90, "", { ...bannerFont, fontSize: "30px", color: "#f4d58f" }).setOrigin(.5).setVisible(false);
                this.bannerTitle.setLetterSpacing && this.bannerTitle.setLetterSpacing(4);
                this.bannerSub = this.add.text(VIEW_W / 2, 120, "", { ...bannerFont, fontStyle: "normal", fontSize: "11px", color: "#c9d8cf" }).setOrigin(.5).setVisible(false);
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
                if (latest) applyData(latest);
                this.input.on(handlers[0], (pointer) => {
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
                    const outside = pointer.x < 0 || pointer.y < 0 || pointer.x > VIEW_W || pointer.y > VIEW_H;
                    finishPull(pointer, outside);
                });
                this.input.on("pointerupoutside", (pointer) => {
                    finishPull(pointer, true);
                });
            },
            update(time, delta) {
                animate(this, time, delta);
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
                const elapsed = (time - this.pathStart) / 1000;
                const point = sampleAt(path, elapsed, 2, false);
                const last = path[path.length - 1];
                if (!this.landed && point && elapsed >= (last.length > 2 ? last[2] : 0)) {
                    // The server path ended: land it with an impact instead of parking the shell.
                    this.landed = true;
                    impact(this, worldToScreen(last[0], last[1]), this.pathWeapon || this.weapon, this.heading);
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
    const onKey = (event) => {
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
        const aim = pullFeedback(sceneRef.seat, pull);
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
            const nextEpoch = data.epoch === undefined ? sceneRef.epoch : data.epoch;
            const epochChanged = nextEpoch !== sceneRef.epoch;
            if (epochChanged) {
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
                    for (let i = 0; i < 5; i++) spawn(sceneRef, burst(VIEW_W * (.15 + i * .175), -6, { count: 10, speed: 90, heading: Math.PI / 2, spread: 1.6, life: 2.2, size: 4 }), [0xf4d58f, 0x8fc5b6, 0xe5b56c, 0xf0e9c8]);
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
            const elapsed = sceneRef.pathStart === null ? 0 : (now - sceneRef.pathStart) / 1000;
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
            paint(sceneRef, pull);
    }
}
