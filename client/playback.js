// Presentation helpers. Sample times come from the server path.
// This file does not integrate a shot.

export function sampleAt(samples, elapsed, timeIndex = 2, holdBefore = false) {
    if (!samples || !samples.length) {
        return null;
    }
    const first = samples[0];
    const firstStamp = first.length > timeIndex ? first[timeIndex] : 0;
    if (!holdBefore && elapsed < firstStamp) {
        return null;
    }
    let chosen = first;
    for (const sample of samples) {
        const stamp = sample.length > timeIndex ? sample[timeIndex] : 0;
        if (stamp <= elapsed) {
            chosen = sample;
        } else {
            break;
        }
    }
    return chosen;
}

export function shellWord(shotReady, yourTurn) {
    if (shotReady === false) {
        return "held";
    }
    if (!yourTurn) {
        return "waiting";
    }
    return "ready";
}

export function stepWatch(current, data, elapsed) {
    const prev = current || {
        path: null,
        collapse: null,
        collapseId: "",
        broken: false,
        angle: 0,
    };
    const path = Array.isArray(data.path) ? replaceSeries(prev.path, data.path) : prev.path;
    const collapse = Array.isArray(data.collapse) ? replaceSeries(prev.collapse, data.collapse) : (prev.collapse || null);
    const played = path !== prev.path ? 0 : elapsed;
    const point = path ? sampleAt(path, played, 2, false) : null;
    const fall = collapse ? sampleAt(collapse, played, 1, true) : null;
    let broken = Boolean(prev.broken);
    let angle = typeof prev.angle === "number" ? prev.angle : 0;
    if (data.phase === "recon") {
        broken = false;
        angle = typeof data.angle === "number" ? data.angle : 0;
    } else if (typeof data.broken === "boolean") {
        broken = data.broken;
        angle = typeof data.angle === "number" ? data.angle : 0;
    }
    return {
        path,
        collapse,
        collapseId: collapse ? (data.collapse_id || prev.collapseId || "") : "",
        shot: point,
        collapseAngle: fall ? fall[0] : null,
        shotTime: point ? String(point[2]) : "",
        shotScreenX: point ? String((point[0] / 40) * 800) : "",
        broken,
        angle,
        shell: shellWord(data.shot_ready !== false, Boolean(data.your_turn)),
    };
}

export function replaceSeries(current, incoming) {
    if (!Array.isArray(incoming)) {
        return current;
    }
    if (!incoming.length) {
        return null;
    }
    if (!sameSeries(current, incoming)) {
        return incoming;
    }
    return current;
}

export function isStale(current, incoming) {
    const epoch = Number(incoming && incoming.epoch !== undefined ? incoming.epoch : 0);
    const revision = Number(incoming && incoming.revision !== undefined ? incoming.revision : 0);
    const currentEpoch = Number(current && current.epoch !== undefined ? current.epoch : 0);
    const currentRevision = Number(current && current.revision !== undefined ? current.revision : 0);
    if (epoch < currentEpoch) {
        return true;
    }
    if (epoch === currentEpoch && revision < currentRevision) {
        return true;
    }
    return false;
}

export function releaseAllowed(input) {
    if (!input || !input.yourTurn || input.outside || input.extraPointer || input.cancelled) {
        return false;
    }
    return true;
}

export function sameSeries(left, right) {
    if (!left || !right || left.length !== right.length) {
        return false;
    }
    if (!left.length) {
        return true;
    }
    const end = left.length - 1;
    const a = left[end];
    const b = right[end];
    return a[0] === b[0] && a[1] === b[1];
}
