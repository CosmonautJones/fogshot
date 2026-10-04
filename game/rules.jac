"""Turn, weapon, and victory rules. This module does not simulate physics."""

import math;
import from game.aim { MIN_POWER, MAX_POWER, angle_ok }

obj MatchRules {
    has phase: str = "recon";
    has turn: int = 0;
    has revision: int = 0;
    has active: str = "A";
    has result: str = "";
    has flare_a: bool = False;
    has flare_b: bool = False;
}

obj ShotDecision {
    has ok: bool;
    has code: str;
    has state: MatchRules;
}

def copy_rules(state: MatchRules) -> MatchRules {
    return MatchRules(
        phase=state.phase,
        turn=state.turn,
        revision=state.revision,
        active=state.active,
        result=state.result,
        flare_a=state.flare_a,
        flare_b=state.flare_b
    );
}

def accept_shot(
    state: MatchRules,
    actor: str,
    revision: int,
    turn: int,
    weapon: str,
    angle: float,
    power: float
) -> ShotDecision {
    if state.phase == "finished" or state.result != "" {
        return ShotDecision(ok=False, code="finished", state=state);
    }
    if actor != state.active {
        return ShotDecision(ok=False, code="actor", state=state);
    }
    if turn != state.turn {
        return ShotDecision(ok=False, code="turn", state=state);
    }
    if revision != state.revision {
        return ShotDecision(ok=False, code="revision", state=state);
    }
    if not math.isfinite(angle) or not math.isfinite(power) {
        return ShotDecision(ok=False, code="nonfinite", state=state);
    }
    if power < MIN_POWER or power > MAX_POWER {
        return ShotDecision(ok=False, code="power", state=state);
    }
    if not angle_ok(actor, angle) {
        return ShotDecision(ok=False, code="angle", state=state);
    }
    expected = "flare" if state.phase == "recon" else "shell";
    if weapon != expected {
        return ShotDecision(ok=False, code="weapon", state=state);
    }
    nxt = copy_rules(state);
    nxt.revision = state.revision + 1;
    nxt.turn = state.turn + 1;
    if weapon == "flare" and actor == "A" {
        nxt.flare_a = True;
    }
    if weapon == "flare" and actor == "B" {
        nxt.flare_b = True;
    }
    if state.phase == "recon" and nxt.flare_a and nxt.flare_b {
        nxt.phase = "combat";
        nxt.active = "A";
    } else {
        nxt.active = "B" if actor == "A" else "A";
    }
    return ShotDecision(ok=True, code="", state=nxt);
}

def resolve_cores(state: MatchRules, core_a: bool, core_b: bool) -> MatchRules {
    nxt = copy_rules(state);
    if (not core_a) and (not core_b) {
        nxt.result = "draw";
        nxt.phase = "finished";
    } elif not core_a {
        nxt.result = "B";
        nxt.phase = "finished";
    } elif not core_b {
        nxt.result = "A";
        nxt.phase = "finished";
    }
    return nxt;
}
