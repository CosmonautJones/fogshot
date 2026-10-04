// Phaser 3.90 scene mount. Jac lambdas do not bind Phaser's scene `this`,
// so the create/input callbacks live in this adapter. The projectile path,
// post pose, and reveal bodies come from the server payload. This file does
// not integrate a shot or decide a hit.
import { AUTO, Game } from "phaser";

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

function drawBodies(pen, bodies, color) {
    for (const body of bodies) {
        if (body.role === "ground" || body.role === "marker" || body.role === "launcher") {
            continue;
        }
        const center = worldToScreen(body.x, body.y);
        if (center.x < -40 || center.x > VIEW_W + 40) {
            continue;
        }
        const height = Math.max(48, (body.h / ARENA_H) * VIEW_H);
        const width = Math.max(14, (body.w / ARENA_W) * VIEW_W);
        pen.save();
        pen.translateCanvas(center.x, center.y);
        pen.rotateCanvas(-body.angle);
        pen.fillStyle(color, 1);
        pen.fillRect(-width / 2, -height / 2, width, height);
        pen.restore();
    }
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
    drawBodies(pen, ownBodies(scene.view), 0xc4a574);
    drawBodies(pen, revealedBodies(scene.view), 0xd27a5a);
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

function remember(parent, data) {
    parent.dataset.seat = data.seat || "";
    parent.dataset.phase = data.phase || "";
    parent.dataset.weapon = data.weapon || "";
    parent.dataset.reveal = data.view && data.view.reveal ? "open" : "closed";
    const seeing = Boolean(data.view && data.view.reveal) || Boolean(data.broken);
    if (seeing && typeof data.angle === "number") {
        parent.dataset.postAngle = String(data.angle);
        parent.dataset.broken = data.broken ? "true" : "false";
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
                this.path = null;
                this.pathIndex = 0;
                paint(this, null);
                this.input.on(handlers[0], (pointer) => {
                    pull = { x: pointer.x, y: pointer.y };
                    paint(this, pull);
                });
                this.input.on(handlers[1], (pointer) => {
                    if (!pull) {
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
                    if (!pull) {
                        return;
                    }
                    const release = { x: pointer.x, y: pointer.y };
                    pull = null;
                    paint(this, null);
                    if (parent) {
                        parent.dataset.pulls = String(Number(parent.dataset.pulls || 0) + 1);
                        parent.dataset.releaseX = String(release.x);
                        parent.dataset.releaseY = String(release.y);
                    }
                    const fire = window.fogshotFire;
                    if (fire) {
                        fire(release.x, release.y);
                    }
                });
            },
            update() {
                const path = this.path;
                if (!path || this.pathIndex >= path.length) {
                    return;
                }
                const point = path[this.pathIndex];
                this.shot = worldToScreen(point[0], point[1]);
                this.pathIndex += 1;
                if (parent) {
                    parent.dataset.shotScreenX = String(this.shot.x);
                }
                paint(this, null);
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
            sceneRef.view = data.view || sceneRef.view;
            if (data.seat) {
                sceneRef.seat = data.seat;
            }
            if (data.path && data.path.length) {
                sceneRef.path = data.path;
                sceneRef.pathIndex = 0;
                sceneRef.shot = worldToScreen(data.path[0][0], data.path[0][1]);
            }
            remember(parent, data);
            paint(sceneRef, pull);
        },
    };
}
