import test from "node:test";
import assert from "node:assert/strict";
import { carveTerrain, craterRims, bodySize } from "../client/presentation.js";

const ridge = Array.from({ length: 41 }, (_, x) => [x, 1 + .5 * Math.sin(x / 7)]);
const at = (points, x) => points.find(p => Math.abs(p[0] - x) < 1e-6);

test("no craters leaves the public ridge untouched", () => {
    assert.deepEqual(carveTerrain(ridge, []), ridge);
    assert.deepEqual(carveTerrain(ridge, undefined), ridge);
    assert.deepEqual(carveTerrain([], [[1, 1, 1]]), []);
});

test("a crater lowers the ground to the circle's lower arc and nowhere else", () => {
    const gy = 1 + .5 * Math.sin(20 / 7);
    const carved = carveTerrain(ridge, [[20, gy, 1.4]]);
    assert.ok(Math.abs(at(carved, 20)[1] - (gy - 1.4)) < 1e-3);
    assert.ok(at(carved, 19.5)[1] < 1 + .5 * Math.sin(19.5 / 7) - .5);
    for (const x of [10, 18, 22, 30]) assert.ok(Math.abs(at(carved, x)[1] - ridge[x][1]) < 1e-9);
    // Deterministic and monotone in x.
    assert.deepEqual(carveTerrain(ridge, [[20, gy, 1.4]]), carved);
    for (let i = 1; i < carved.length; i++) assert.ok(carved[i][0] > carved[i - 1][0]);
});

test("overlapping craters dig deeper, and your launcher pad never caves in", () => {
    const gy = 1 + .5 * Math.sin(20 / 7);
    const twice = carveTerrain(ridge, [[20, gy, 1.4], [20, gy - 1.4, 1.4]]);
    assert.ok(at(twice, 20)[1] < gy - 2.7);
    const padded = carveTerrain(ridge, [[5, ridge[5][1], 1.4]], [5]);
    for (const [x, y] of padded) if (Math.abs(x - 5) <= 2.5) assert.ok(Math.abs(y - (1 + .5 * Math.sin(x / 7))) < 1e-3);
    assert.equal(craterRims(ridge, [[5, ridge[5][1], 1.4]], [5]).length, 0);
    assert.equal(craterRims(ridge, [[20, gy, 1.4]]).length, 1);
});

test("garbage crater rows are ignored", () => {
    assert.deepEqual(carveTerrain(ridge, [[NaN, 1, 1], [1, 1], "x", [3, 1, -1]]), ridge);
});

test("debris pieces keep their server size", () => {
    const size = bodySize({ role: "debris-stone", w: .4, h: .3 });
    assert.ok(size.width > 0 && size.height > 0);
});
