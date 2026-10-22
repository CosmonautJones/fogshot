import assert from "node:assert/strict";
import test from "node:test";
import { trianglePoints, headingOf, easeOutBack, easeOutCubic, burst, stepShards, bannerFor, recordAfter, recordLabel } from "../client/presentation.js";

const close = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) < eps, `${a} != ${b}`);

test("triangle nose points along the requested angle and the shape is symmetric", () => {
    const [nose, left, right] = trianglePoints(10, 10, 5, 0);
    close(nose.x, 15); close(nose.y, 10);
    close(left.x, right.x); close(left.y - 10, -(right.y - 10));
    assert.ok(left.x < 10, "rear corners sit behind the centre");
    const [up] = trianglePoints(0, 0, 2, -Math.PI / 2);
    close(up.x, 0); close(up.y, -2);
});
test("heading uses atan2 and ignores sub-pixel jitter", () => {
    close(headingOf({x: 0, y: 0}, {x: 0, y: 10}), Math.PI / 2);
    close(headingOf({x: 0, y: 0}, {x: -3, y: 0}), Math.PI);
    assert.equal(headingOf({x: 0, y: 0}, {x: .1, y: .1}), null);
    assert.equal(headingOf(null, {x: 1, y: 1}), null);
});
test("easing curves start at 0, end at 1 and clamp outside the range", () => {
    close(easeOutBack(0), 0); close(easeOutBack(1), 1); close(easeOutCubic(0), 0); close(easeOutCubic(1), 1);
    assert.ok(easeOutBack(.7) > 1, "back easing overshoots for a little pop");
    close(easeOutCubic(5), 1); close(easeOutBack(-2), 0);
});
test("shards fly outward, fall under gravity and expire", () => {
    let seed = 1; const rand = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
    const shards = burst(100, 100, {count: 12, rand});
    assert.equal(shards.length, 12);
    let live = shards;
    live = stepShards(live, .05);
    assert.ok(live.every(s => Math.hypot(s.x - 100, s.y - 100) > 0));
    for (let i = 0; i < 40; i++) live = stepShards(live, .05);
    assert.equal(live.length, 0, "every shard expires within its life");
});
test("field banner states the goal on your turn and the outcome when finished", () => {
    assert.equal(bannerFor({}), null);
    assert.match(bannerFor({seat: "A", your_turn: true, phase: "recon"}).sub, /flare/);
    assert.match(bannerFor({seat: "A", your_turn: true, phase: "combat"}).sub, /Shell/);
    assert.equal(bannerFor({seat: "A", your_turn: false, phase: "combat"}), null);
    assert.equal(bannerFor({seat: "A", result: "A"}).kind, "victory");
    assert.equal(bannerFor({seat: "B", result: "A"}).kind, "defeat");
    assert.equal(bannerFor({seat: "B", result: "draw"}).kind, "draw");
});
test("record counts each finished duel once and tracks the best streak", () => {
    let r = recordAfter(null, {seat: "A", result: "A"}, "r1:1");
    r = recordAfter(r, {seat: "A", result: "A"}, "r1:1");
    assert.equal(r.wins, 1, "reload of the same duel is not counted twice");
    r = recordAfter(r, {seat: "A", result: "A"}, "r1:2");
    assert.deepEqual([r.wins, r.streak, r.best], [2, 2, 2]);
    r = recordAfter(r, {seat: "A", result: "B"}, "r1:3");
    assert.deepEqual([r.losses, r.streak, r.best], [1, 0, 2]);
    r = recordAfter(r, {seat: "A", result: ""}, "r1:4");
    assert.equal(r.counted.length, 3, "unfinished duels are ignored");
    assert.equal(recordLabel(r), "RECORD 2-1 · BEST 2");
    assert.equal(recordLabel(null), "RECORD 0-0");
});
