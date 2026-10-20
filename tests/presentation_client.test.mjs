import assert from "node:assert/strict";
import test from "node:test";
import { bodySize, pullFeedback, hudState, protocolPull, observationAt } from "../client/presentation.js";

test("clipped reveal geometry is never expanded into an inferred structure", () => {
    assert.deepEqual(bodySize({ w: 0.14, h: 0.12 }), { width: 2.8000000000000003, height: 3 });
    assert.deepEqual(bodySize({ w: 0, h: 0 }), { width: 0, height: 0 });
});
test("pull guide stays short and only uses the local gesture", () => {
    const aim = pullFeedback("A", { x: 20, y: 390 });
    assert.equal(aim.valid, true);
    assert.ok(aim.guide.every(p => p.x < 400));
    assert.ok(aim.guide.length <= 8);
    assert.ok(aim.power <= 22);
    assert.equal(pullFeedback("A", { x: 200, y: 300 }).valid, false);
    assert.equal(pullFeedback("A", { x: NaN, y: 0 }).valid, false);
});
test("seat B guide mirrors the existing server input mapping", () => {
    const aim = pullFeedback("B", { x: 780, y: 390 });
    assert.equal(aim.valid, true);
    assert.deepEqual(protocolPull("B", {x:780,y:390}), {x:20,y:390});
    assert.deepEqual(protocolPull("A", {x:20,y:390}), {x:20,y:390});
    assert.ok(aim.guide.every(p => p.x > 400));
});
test("HUD uses explicit outcomes and never labels supply as shot authority", () => {
    assert.equal(hudState({seat:"A",your_turn:true,own_powered:false,shot_ready:true,phase:"combat"}).turn, "Your turn");
    assert.equal(hudState({seat:"A",result:"B"}).turn, "Outpost lost");
    assert.equal(hudState({seat:"B",result:"B"}).turn, "Victory");
    assert.equal(hudState({result:"draw"}).turn, "Draw");
    assert.equal(hudState({seat:"A"}).enemy, "—");
});

test("a delayed expired poll cannot restore an enemy break after local closure", () => {
    const data = { seat: "A", broken: true, angle: .9, reveal_until: 1000,
        reveal_x: 21, reveal_y: 1, reveal_radius: 4, path: [[21,1,1]],
        collapse: [[.9,1]], collapse_id: "enemy-post", view: {own: [], reveal: {bodies: [{id:"enemy-post"}]}} };
    assert.equal(observationAt(data, 999), data);
    const closed = observationAt(data, 1000);
    assert.equal(closed.view.reveal, null);
    assert.deepEqual(closed.path, []);
    assert.deepEqual(closed.collapse, []);
    assert.equal(closed.collapse_id, "");
    assert.equal(closed.broken, false);
    assert.equal(closed.angle, 0);
    assert.equal(closed.reveal_until, 0);
    // The legacy break/angle fields describe B's own post, which remains entitled.
    const own = observationAt({...data, seat:"B"}, 1001);
    assert.equal(own.broken, true);
    assert.equal(own.angle, .9);
});

test("one observed timestamp arms expiry even if wall time advances during processing", () => {
    const data = {seat:"A", broken:true, angle:.9, reveal_until:1000, view:{own:[],reveal:{bodies:[]}}};
    let clock = 999;
    const observedAt = clock;
    const accepted = observationAt(data, observedAt);
    clock = 1000;
    // All decisions for this response use observedAt; its deadline stays armed.
    assert.equal(accepted.reveal_until > observedAt, true);
    const expired = observationAt(accepted, clock);
    assert.equal(expired.view.reveal, null);
    assert.equal(expired.broken, false);
});
