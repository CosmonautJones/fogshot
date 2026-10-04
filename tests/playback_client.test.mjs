import assert from "node:assert/strict";
import test from "node:test";
import { isStale, releaseAllowed, replaceSeries, sampleAt, stepWatch } from "../client/playback.js";

test("elapsed time selects the sample, not the frame index", () => {
    const path = [
        [0, 0, 0],
        [10, 0, 1],
        [20, 0, 2],
    ];
    assert.equal(sampleAt(path, 0)[0], 0);
    assert.equal(sampleAt(path, 1.5)[0], 10);
    assert.equal(sampleAt(path, 5)[0], 20);
    let point = path[0];
    for (let frame = 0; frame < 120; frame += 1) {
        point = sampleAt(path, 1);
    }
    assert.equal(point[0], 10);
});

test("a later path sample stays hidden until its timestamp", () => {
    const tail = [
        [18.5, 1.2, 4.7],
        [20.7, 1.1, 5.1],
    ];
    assert.equal(sampleAt(tail, 0, 2, false), null);
    assert.equal(sampleAt(tail, 4.6, 2, false), null);
    assert.equal(sampleAt(tail, 4.7, 2, false)[0], 18.5);
    const fall = [
        [0.22, 0.1],
        [0.95, 4.7],
    ];
    assert.equal(sampleAt(fall, 0, 1, true)[0], 0.22);
    assert.equal(sampleAt(fall, 4.7, 1, true)[0], 0.95);
});

test("an empty path clears playback and a new path does not keep the old one", () => {
    const first = [[6, 4, 0.1]];
    const second = [[6, 4, 0.1], [12, 3, 1.2]];
    assert.equal(replaceSeries(first, []), null);
    assert.equal(replaceSeries(first, second), second);
    assert.equal(replaceSeries(second, second), second);
});

test("an empty watch stops the dot and drops a break the server cleared", () => {
    const open = stepWatch(null, {
        path: [[6, 4, 0], [16.2, 1, 3.44], [20.508, 1, 7.78]],
        collapse: [[0.22, 0.1], [0.95, 7.78]],
        collapse_id: "enemy-post",
        broken: true,
        angle: 0.9518854371891518,
        phase: "combat",
        your_turn: false,
        shot_ready: true,
        view: { reveal: { bodies: [] } },
    }, 3.44);
    assert.equal(open.broken, true);
    assert.ok(Number(open.shotScreenX) < 400);
    const closed = stepWatch(open, {
        path: [],
        collapse: [],
        broken: false,
        angle: 0,
        phase: "combat",
        your_turn: false,
        shot_ready: true,
        view: {},
    }, 5);
    assert.equal(closed.path, null);
    assert.equal(closed.collapse, null);
    assert.equal(closed.shot, null);
    assert.equal(closed.shotScreenX, "");
    assert.equal(closed.shotTime, "");
    assert.equal(closed.broken, false);
    assert.equal(closed.angle, 0);
    assert.equal(closed.shell, "waiting");
});

test("a filtered tail is not on screen while the shooter is still at the start", () => {
    const other = stepWatch(null, {
        path: [[18.48, 1.2, 4.78], [20.508, 1.1, 7.78]],
        collapse: [],
        broken: false,
        angle: 0,
        phase: "combat",
        your_turn: true,
        shot_ready: true,
        view: {},
    }, 0.33);
    assert.equal(other.shot, null);
    assert.equal(other.shotTime, "");
    assert.equal(other.shell, "ready");
});

test("an older poll does not replace a newer revision", () => {
    assert.equal(isStale({ epoch: 2, revision: 3 }, { epoch: 2, revision: 2 }), true);
    assert.equal(isStale({ epoch: 2, revision: 3 }, { epoch: 1, revision: 9 }), true);
    assert.equal(isStale({ epoch: 2, revision: 3 }, { epoch: 2, revision: 3 }), false);
    assert.equal(isStale({ epoch: 2, revision: 3 }, { epoch: 3, revision: 0 }), false);
});

test("cancel, a second pointer, and the opponent turn do not fire", () => {
    const allowed = { yourTurn: true, outside: false, extraPointer: false, cancelled: false };
    assert.equal(releaseAllowed(allowed), true);
    assert.equal(releaseAllowed({ ...allowed, yourTurn: false }), false);
    assert.equal(releaseAllowed({ ...allowed, outside: true }), false);
    assert.equal(releaseAllowed({ ...allowed, extraPointer: true }), false);
    assert.equal(releaseAllowed({ ...allowed, cancelled: true }), false);
});
