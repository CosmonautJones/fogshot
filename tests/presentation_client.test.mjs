import assert from "node:assert/strict";
import test from "node:test";
import { bodySize, pullFeedback, hudState, protocolPull } from "../client/presentation.js";

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
