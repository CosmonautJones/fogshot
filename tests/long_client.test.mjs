import test from "node:test";
import assert from "node:assert/strict";
import { CLASSIC_FIELD, fieldOf, fieldPixels, toScreen, dragPull, padFromAim, longAim, previewArc, cameraHome, cameraOn, clampScroll, overviewRect, overviewToWorld, rangeMarks, terrainPolygon, LONG_FLOOR } from "../client/presentation.js";

const LONG = fieldOf({ field: { mode: "long", w: 160, h: 96, pad_x: 400, pad_y: 200, full_pull: 240, min_pull: 12, v_max: 44, gravity: 9.81, drag: .97 } });
const VIEW = { w: 800, h: 400 };

test("classic payloads keep the 40 x 16 field and its screen mapping", () => {
    assert.equal(fieldOf({}), CLASSIC_FIELD);
    assert.equal(fieldOf({ field: { mode: "classic", w: 40, h: 16 } }), CLASSIC_FIELD);
    assert.deepEqual(toScreen(CLASSIC_FIELD, 20, 8), { x: 400, y: 200 });
    assert.deepEqual(fieldPixels(CLASSIC_FIELD), { w: 800, h: 400 });
    assert.deepEqual(fieldPixels(LONG), { w: 3200, h: 2400 + LONG_FLOOR });
    assert.equal(terrainPolygon([[0, 0], [160, 0]], 96, LONG_FLOOR).at(-1).y, 2400 + LONG_FLOOR);
});

test("long aim mirrors the server pad protocol for both seats", () => {
    const pull = dragPull("A", null, { x: 500, y: 200 }, { x: 350, y: 310 });
    assert.deepEqual(pull, { x: 150, y: 110 });
    const a = longAim("A", pull, LONG);
    assert.ok(a.valid);
    assert.ok(Math.abs(a.degrees - Math.atan2(110, 150) * 180 / Math.PI) < 1e-9);
    assert.ok(Math.abs(a.power - Math.hypot(150, 110) / 240 * 44) < 1e-9);
    assert.deepEqual(a.pointer, { x: 250, y: 310 });
    // Seat B pulls the other way on screen; the pad pull and wire pointer are the same.
    const mirrored = dragPull("B", null, { x: 300, y: 200 }, { x: 450, y: 310 });
    assert.deepEqual(mirrored, pull);
    const b = longAim("B", mirrored, LONG);
    assert.ok(Math.abs(b.angle - (Math.PI - a.angle)) < 1e-12);
    assert.deepEqual(b.pointer, a.pointer);
    // Past full length the pull is clamped; tiny or backward pulls do not aim.
    const long = longAim("A", { x: 480, y: 0 }, LONG);
    assert.equal(long.fraction, 1);
    assert.deepEqual(long.pointer, { x: 160, y: 200 });
    assert.equal(longAim("A", { x: 5, y: 5 }, LONG).valid, false);
    assert.equal(longAim("A", { x: -100, y: 30 }, LONG).valid, false);
    // Relative drags add to the locked aim.
    assert.deepEqual(dragPull("A", { x: 100, y: 50 }, { x: 10, y: 10 }, { x: 0, y: 30 }), { x: 110, y: 70 });
    const round = padFromAim(a.padAngle, a.fraction, LONG);
    assert.ok(Math.abs(round.x - 150) < 1e-9 && Math.abs(round.y - 110) < 1e-9);
});

test("the preview arc is partial: a short bend, never the landing", () => {
    const aim = longAim("A", padFromAim(Math.PI / 4, 1, LONG), LONG);
    const arc = previewArc(aim, { x: 8, y: 4 }, LONG);
    assert.ok(arc.length >= 4 && arc.length <= 8);
    const last = arc.at(-1);
    assert.ok(last.x - 8 < 14, "preview stops within ~14 m of a 140+ m shot");
    assert.ok(last.y > 4, "still climbing: no apex, no descent, no landing");
    assert.ok(arc[1].heading < arc[0].heading, "but it bends under gravity");
    assert.deepEqual(previewArc(longAim("A", { x: 1, y: 1 }, LONG), { x: 8, y: 4 }, LONG), []);
});

test("camera homes on your own launcher, follows anything and stays in bounds", () => {
    const world = fieldPixels(LONG);
    assert.equal(cameraHome("A", toScreen(LONG, 8, 4), VIEW, world).x, 0);
    assert.equal(cameraHome("B", toScreen(LONG, 152, 4), VIEW, world).x, world.w - VIEW.w);
    const mid = cameraOn({ x: 1600, y: 1200 }, VIEW, world);
    assert.deepEqual(mid, { x: 1200, y: 1000 });
    assert.deepEqual(clampScroll({ x: -50, y: 99999 }, VIEW, world), { x: 0, y: world.h - VIEW.h });
    const strip = overviewRect(VIEW, 1);
    assert.equal(overviewToWorld(strip.x, strip, world), 0);
    assert.equal(overviewToWorld(strip.x + strip.w, strip, world), world.w);
    assert.ok(overviewRect(VIEW, 2.1).h > strip.h, "a thicker strip for small phone canvases");
});

test("range marks count out from your launcher toward the enemy", () => {
    const a = rangeMarks("A", 8, LONG);
    assert.deepEqual(a.slice(0, 2), [{ x: 28, label: "20 m" }, { x: 48, label: "40 m" }]);
    const b = rangeMarks("B", 152, LONG);
    assert.equal(b[0].x, 132);
    assert.ok(a.length >= 7 && a.every(m => m.x < 160));
});
