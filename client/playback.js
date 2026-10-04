// Presentation helpers. Sample times come from the server path.
// This file does not integrate a shot.

export function sampleAt(samples, elapsed, timeIndex = 2) {
    if (!samples || !samples.length) {
        return null;
    }
    let chosen = samples[0];
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
