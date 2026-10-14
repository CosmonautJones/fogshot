// Phaser 3.90 scene mount. Jac lambdas do not bind Phaser's scene `this`,
// so the create/input callbacks live in this adapter. The projectile path,
// post pose, and reveal bodies come from the server payload. This file does
// not integrate a shot or decide a hit.
import { AUTO, Game, Scale } from "phaser";
import "../assets/field.css";
import { bodySize, pullFeedback, hudState, protocolPull } from "./presentation.js";
import { isStale, releaseAllowed, sampleAt, stepWatch } from "./playback.js";

const ARENA_W = 40;
const ARENA_H = 16;
const VIEW_W = 800;
const VIEW_H = 400;

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
        pen.fillStyle(aim.valid ? 0xf1d18b : 0xb98472, 1);
        for (const point of aim.guide) pen.fillCircle(point.x, point.y, 2);
        pen.lineStyle(2, aim.valid ? 0xf1d18b : 0xb98472, .9);
        pen.beginPath(); pen.arc(launch.x, launch.y, 29, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * aim.power / 22); pen.strokePath();
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
    Object.assign(parent.dataset, { reveal: "closed", shotScreenX: "", shotTime: "", broken: "false", postAngle: "0" });
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
    if (scene.shot) {
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
    scene.launchLabel.setText(scene.yourTurn ? "PULL TO FIRE" : "STAND BY");
}

function renderHud(data) {
    const status = hudState(data);
    const put = (id, text) => { const element = document.getElementById(id); if (element && element.textContent !== text) element.textContent = text; };
    const rematch = document.getElementById("fogshot-rematch");
    if (rematch) { rematch.disabled = data.phase !== "finished"; rematch.title = data.phase === "finished" ? "Play another duel" : "Available after the duel"; }
    put("fogshot-room", data.room || "------");
    put("fogshot-turn", status.turn);
    put("fogshot-weapon", status.weapon);
    put("fogshot-supply", status.supply);
    put("fogshot-cores", `Own: ${status.core}\nEnemy: ${status.enemy}`);
    put("fogshot-observation", data.view && data.view.reveal ? "OBSERVATION OPEN / REMEMBER THIS" : "ENEMY STRUCTURES HIDDEN");
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
                this.fogPen = this.add.graphics();
                const labelStyle = { fontFamily: "Arial", fontSize: "9px", color: "#b8d6c6", backgroundColor: "#102a34", padding: { x: 5, y: 3 }, resolution: 2 };
                this.coreLabel = this.add.text(0, 0, "", labelStyle).setOrigin(.5);
                this.launchLabel = this.add.text(0, 0, "", { ...labelStyle, fontSize: "8px", color: "#dfd6ac" }).setOrigin(.5);
                this.fieldParent = parent;
                const resizeLabels = () => {
                    const size = Math.max(9, 10 / Math.max(.2, parent.clientWidth / VIEW_W));
                    this.coreLabel.setFontSize(size);
                    this.launchLabel.setFontSize(size);
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
                    activeId = pointer.id;
                    pull = { x: pointer.x, y: pointer.y };
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
            update(time) {
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
                if (point) {
                    this.shot = worldToScreen(point[0], point[1]);
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
                pull = null; keyboardPull = null; paint(sceneRef, null);
            }
            return;
        }
        if (!keyboardPull) cancelGesture();
        keyboardPull ||= { x: sceneRef.seat === "B" ? 780 : 20, y: 340 };
        if (event.key === "ArrowLeft") keyboardPull.x = Math.max(0, keyboardPull.x - 4);
        if (event.key === "ArrowRight") keyboardPull.x = Math.min(799, keyboardPull.x + 4);
        if (event.key === "ArrowUp") keyboardPull.y = Math.max(0, keyboardPull.y - 4);
        if (event.key === "ArrowDown") keyboardPull.y = Math.min(399, keyboardPull.y + 4);
        pull = { ...keyboardPull };
        paint(sceneRef, pull);
        const aim = pullFeedback(sceneRef.seat, pull);
        const hint = document.getElementById("fogshot-pull");
        if (hint) hint.textContent = aim.valid ? `Pull ${Math.round(aim.power / 22 * 100)}%. Enter to launch, Escape to cancel.` : "Adjust the pull behind the launcher.";
    };
    parent.addEventListener("keydown", onKey);
    const onBlur = () => cancelGesture();
    window.addEventListener("blur", onBlur);
    const onVisible = () => { if (!document.hidden && sceneRef) paint(sceneRef, pull); };
    document.addEventListener("visibilitychange", onVisible);
    parent.dataset.fogshotHandlers = String(handlers.length);
    parent.dataset.reveal = "closed";
    return {
        destroy() {
            parent.removeEventListener("keydown", onKey);
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
            sceneRef.view = data.view || sceneRef.view;
            sceneRef.yourTurn = Boolean(data.your_turn);
            sceneRef.weapon = data.weapon || sceneRef.weapon;
            if (sceneRef.revealTimer) { clearTimeout(sceneRef.revealTimer); sceneRef.revealTimer = null; }
            if (data.view && data.view.reveal && data.reveal_radius > 0 && data.reveal_until > Date.now()) {
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
                if (data.view && data.view.reveal) data = { ...data, view: { ...data.view, reveal: null }, path: [], collapse: [] };
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
