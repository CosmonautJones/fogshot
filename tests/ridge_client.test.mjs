import test from "node:test";
import assert from "node:assert/strict";
import { pullFeedback, ridgeLines, ridgeRandom, terrainPolygon, ridgeLabel } from "../client/presentation.js";

test("pull feedback follows a generated launcher", () => {
    const classic = pullFeedback("A", { x: 20, y: 390 });
    assert.deepEqual(pullFeedback("A", { x: 20, y: 390 }, { x: 6, y: 4 }), classic);
    const moved = pullFeedback("A", { x: 20, y: 390 }, { x: 6.5, y: 4.8 });
    assert.equal(moved.origin.x, 130);
    assert.equal(moved.origin.y, 280);
    assert.ok(moved.valid);
    assert.ok(Math.abs(moved.power - Math.hypot(5.5, 4.8 - 0.4)) < 1e-9);
    const b = pullFeedback("B", { x: 780, y: 390 }, { x: 33.5, y: 4.8 });
    assert.ok(b.valid && b.origin.x === 670);
});

test("ridgelines are seeded by the public ridge and stay on screen", () => {
    assert.deepEqual(ridgeLines(0), []);
    const one = ridgeLines(48213);
    assert.deepEqual(ridgeLines(48213), one);
    assert.notDeepEqual(ridgeLines(48214), one);
    assert.equal(one.length, 3);
    for (const layer of one) for (const p of layer) assert.ok(p.y > 150 && p.y < 330 && p.x >= 0 && p.x <= 800);
    const rand = ridgeRandom(7);
    for (let i = 0; i < 100; i++) { const v = rand(); assert.ok(v >= 0 && v < 1); }
});

test("terrain polygon closes to the bottom edge and labels name the ridge", () => {
    const poly = terrainPolygon([[-2, 0], [20, 1.2], [42, 0]]);
    assert.equal(poly.length, 5);
    assert.deepEqual(poly[1], { x: 400, y: 370 });
    assert.equal(poly[3].y, 400);
    assert.deepEqual(terrainPolygon(null), []);
    assert.equal(ridgeLabel({ ridge: 48213, layout_name: "Ridge #48213" }), "RIDGE #48213");
    assert.equal(ridgeLabel({ ridge: 0, layout_name: "Classic ridge" }), "CLASSIC RIDGE");
    assert.equal(ridgeLabel({ ridge: 9, layout_name: "Fold #9", mode: "practice", bot_level: 3 }), "FOLD #9 · BOT LV 3");
    assert.equal(ridgeLabel({}), "01 / RIDGELINE");
});
