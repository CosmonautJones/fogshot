// Phaser 3.90 scene mount. Jac lambdas do not bind Phaser's scene `this`,
// so the create/input callbacks live in this adapter. The projectile path,
// post pose, and reveal bodies come from the server payload. This file does
// not integrate a shot or decide a hit.
import { AUTO, Game } from "phaser";
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

function drawBodies(pen, bodies, color, collapseAngle, collapseId) {
    for (const body of bodies) {
        if (body.role === "ground" || body.role === "marker" || body.role === "launcher") {
            continue;
        }
        const center = worldToScreen(body.x, body.y);
        if (center.x < -40 || center.x > VIEW_W + 40) {
            continue;
        }
        const falling = body.role === "post" && collapseId && body.id === collapseId && typeof collapseAngle === "number";
        const angle = falling ? collapseAngle : body.angle;
        pen.save();
        pen.translateCanvas(center.x, center.y);
        pen.rotateCanvas(-angle);
        if (body.role === "core") {
            const size = Math.max(22, (body.w / ARENA_W) * VIEW_W);
            pen.fillStyle(body.alive === false ? 0x4a4038 : 0xe7c27a, 1);
            pen.fillRect(-size / 2, -size / 2, size, size);
        } else {
            const height = Math.max(48, (body.h / ARENA_H) * VIEW_H);
            const width = Math.max(14, (body.w / ARENA_W) * VIEW_W);
            pen.fillStyle(color, 1);
            pen.fillRect(-width / 2, -height / 2, width, height);
        }
        pen.restore();
    }
}

function drawLamp(pen, scene) {
    const x = scene.seat === "B" ? 720 : 80;
    const y = 36;
    const powered = scene.powered !== false;
    pen.fillStyle(powered ? 0xf2d48a : 0x1a1f27, 1);
    pen.fillCircle(x, y, 11);
    pen.lineStyle(3, powered ? 0xf2d48a : 0x5c6770, 1);
    pen.strokeCircle(x, y, 18);
}

function launcherOf(scene) {
    const own = ownBodies(scene.view);
    for (const body of own) {
        if (body.role === "launcher") {
            return worldToScreen(body.x, body.y);
        }
    }
    if (scene.seat === "B") {
        return worldToScreen(34, 4);
    }
    return worldToScreen(6, 4);
}

function paint(scene, pull) {
    const pen = scene.fogPen || scene.add.graphics();
    scene.fogPen = pen;
    pen.clear();
    pen.fillStyle(0x1b2430, 1);
    pen.fillRect(0, 0, VIEW_W, VIEW_H);
    pen.fillStyle(0x0c1016, 0.94);
    if (scene.seat === "B") {
        pen.fillRect(0, 0, VIEW_W / 2, VIEW_H);
    } else {
        pen.fillRect(VIEW_W / 2, 0, VIEW_W / 2, VIEW_H);
    }
    drawBodies(pen, ownBodies(scene.view), 0xc4a574, scene.collapseAngle, scene.collapseId);
    drawBodies(pen, revealedBodies(scene.view), 0xd27a5a, scene.collapseAngle, scene.collapseId);
    drawLamp(pen, scene);
    const launch = launcherOf(scene);
    scene.launch = launch;
    pen.fillStyle(0xd7e2ea, 1);
    pen.fillCircle(launch.x, launch.y, 8);
    pen.lineStyle(2, 0x8fd0c6, 1);
    pen.strokeCircle(launch.x, launch.y, 18);
    if (pull) {
        pen.lineBetween(launch.x, launch.y, pull.x, pull.y);
    }
    if (scene.shot) {
        pen.fillStyle(0xf2d48a, 1);
        pen.fillCircle(scene.shot.x, scene.shot.y, 6);
    }
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
    const game = new Game({
        type: AUTO,
        parent,
        width: VIEW_W,
        height: VIEW_H,
        backgroundColor: "#14181f",
        scene: {
            create() {
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
                const finishPull = (pointer, outside) => {
                    if (!pull || pointer.id !== activeId) {
                        return;
                    }
                    const release = { x: pointer.x, y: pointer.y };
                    const yourTurn = Boolean(parent && parent.dataset.yourTurn === "true");
                    const allowed = releaseAllowed({
                        yourTurn,
                        outside,
                        extraPointer: false,
                        cancelled: outside,
                    });
                    pull = null;
                    activeId = null;
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
                        fire(release.x, release.y);
                    }
                };
                paint(this, null);
                this.input.on(handlers[0], (pointer) => {
                    if (pull) {
                        if (parent) {
                            parent.dataset.extraPointer = "true";
                        }
                        return;
                    }
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
    parent.dataset.fogshotHandlers = String(handlers.length);
    parent.dataset.reveal = "closed";
    return {
        destroy() {
            game.destroy(true);
        },
        apply(raw) {
            if (!sceneRef) {
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
            if (nextEpoch !== sceneRef.epoch) {
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
            sceneRef.view = data.view || sceneRef.view;
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
        },
    };
}
