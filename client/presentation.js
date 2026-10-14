// Presentation math only. Authority, clipping and trajectory samples stay on the server.
export function bodySize(body) {
    return { width: Math.max(0, body.w * 20), height: Math.max(0, body.h * 25) };
}

export function pullFeedback(seat, pointer) {
    const origin = { x: seat === "B" ? 680 : 120, y: 300 };
    const wx = pointer.x / 20;
    const dx = (seat === "B" ? 34 : 6) - wx;
    const dy = 4 - (1 - pointer.y / 400) * 16;
    const rawPower = Math.hypot(dx, dy);
    const angle = Math.atan2(dy, dx);
    const power = Math.min(22, rawPower);
    const valid = Number.isFinite(power) && rawPower >= 1 && Math.cos(angle) * (seat === "B" ? -1 : 1) > 0.25 && Math.sin(angle) > -0.35;
    const guide = [];
    // A short direction cue, not a landing or collision prediction.
    if (valid) {
        for (let n = 1; n <= 7; n++) {
            const distance = n * 6;
            const x = origin.x + Math.cos(angle) * distance;
            const y = origin.y - Math.sin(angle) * distance;
            if ((seat === "B" && x <= 400) || (seat !== "B" && x >= 400)) break;
            guide.push({ x, y });
        }
    }
    return { valid, power, angle, guide, origin };
}

export function hudState(data) {
    const result = data.result || "";
    const draw = result.toLowerCase() === "draw";
    return {
        turn: result ? (draw ? "Draw" : result === data.seat ? "Victory" : "Outpost lost") : data.your_turn ? "Your turn" : data.seat ? "Opponent aiming" : "Connecting…",
        weapon: data.phase === "recon" ? "Scout flare" : "Standard shell",
        supply: data.own_powered === false ? "Supply cut · shell available" : "Supply connected",
        enemy: data.enemy_cores === undefined ? "—" : String(data.enemy_cores),
        core: data.own_core === false ? "Lost" : "Standing",
    };
}

// The server protocol mirrors B input; gestures themselves stay in screen space.
export function protocolPull(seat, pointer) {
    return { x: seat === "B" ? 800 - pointer.x : pointer.x, y: pointer.y };
}
