import assert from "node:assert/strict";
import test from "node:test";
import { isStale, releaseAllowed, sampleAt } from "../client/playback.js";

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
