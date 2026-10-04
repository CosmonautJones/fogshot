// Phaser 3.90 scene mount. Jac lambdas do not bind Phaser's scene `this`,
// so the create/input callbacks live in this adapter. Named exports match
// `import from "phaser" { Game, AUTO }`, which jac check accepts.
import { AUTO, Game } from "phaser";

const LAUNCH_X = 120;
const LAUNCH_Y = 280;
const MIDLINE = 400;

function paint(scene, pull) {
    const pen = scene.fogPen || scene.add.graphics();
    scene.fogPen = pen;
    pen.clear();
    pen.fillStyle(0x1b2430, 1);
    pen.fillRect(0, 0, MIDLINE, 400);
    pen.fillStyle(0x0c1016, 0.94);
    pen.fillRect(MIDLINE, 0, 400, 400);
    pen.fillStyle(0xc4a574, 1);
    pen.fillRect(148, 168, 14, 150);
    pen.fillStyle(0xd7e2ea, 1);
    pen.fillCircle(LAUNCH_X, LAUNCH_Y, 8);
    pen.lineStyle(2, 0x8fd0c6, 1);
    pen.strokeCircle(LAUNCH_X, LAUNCH_Y, 18);
    if (pull) {
        pen.lineBetween(LAUNCH_X, LAUNCH_Y, pull.x, pull.y);
    }
    if (scene.shot) {
        pen.fillStyle(0xf2d48a, 1);
        pen.fillCircle(scene.shot.x, scene.shot.y, 6);
    }
}

export function mountField(parent) {
    if (!parent) {
        return { destroy() {} };
    }
    const handlers = ["pointerdown", "pointermove", "pointerup"];
    let pull = null;
    const game = new Game({
        type: AUTO,
        parent,
        width: 800,
        height: 400,
        backgroundColor: "#14181f",
        scene: {
            create() {
                this.shot = null;
                paint(this, null);
                this.input.on(handlers[0], (pointer) => {
                    pull = { x: pointer.x, y: pointer.y };
                    this.shot = null;
                    paint(this, pull);
                });
                this.input.on(handlers[1], (pointer) => {
                    if (!pull) {
                        return;
                    }
                    pull = { x: pointer.x, y: pointer.y };
                    paint(this, pull);
                });
                this.input.on(handlers[2], () => {
                    if (!pull) {
                        return;
                    }
                    const dx = LAUNCH_X - pull.x;
                    const dy = LAUNCH_Y - pull.y;
                    pull = null;
                    const span = Math.hypot(dx, dy) || 1;
                    const power = Math.min(1, span / 90);
                    const dirX = dx / span;
                    const dirY = dy / span;
                    const endX = Math.min(MIDLINE, Math.max(0, LAUNCH_X + dirX * power * (MIDLINE - LAUNCH_X)));
                    const endY = Math.min(390, Math.max(10, LAUNCH_Y + dirY * power * 160));
                    this.shot = { x: LAUNCH_X, y: LAUNCH_Y, endX, endY, t: 0 };
                    paint(this, null);
                });
            },
            update() {
                const shot = this.shot;
                if (!shot || shot.t >= 1) {
                    return;
                }
                shot.t = Math.min(1, shot.t + 0.04);
                shot.x = LAUNCH_X + (shot.endX - LAUNCH_X) * shot.t;
                shot.y = LAUNCH_Y + (shot.endY - LAUNCH_Y) * shot.t;
                paint(this, null);
            },
        },
    });
    parent.dataset.fogshotHandlers = String(handlers.length);
    return {
        destroy() {
            game.destroy(true);
        },
    };
}
