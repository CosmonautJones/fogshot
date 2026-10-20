"""Practice decisions consume legal observations and bounded remembered glimpses."""
import json;
import from game.aim { release_pull }
import from game.practice_bot { choose, learn, new_memory }

def _wire(turn: int = 1, phase: str = "recon") -> str {
    return json.dumps({"seat": "B", "your_turn": True, "phase": phase,
        "turn": turn, "epoch": 1, "reveal_until": 0,
        "view": {"own": [], "public": [], "reveal": None}});
}

test "practice decisions are deterministic legal seat B pulls" {
    memory = new_memory(1);
    first = json.loads(choose(_wire(), memory));
    assert first["ready"];
    assert first["weapon"] == "flare";
    assert choose(_wire(), memory) == choose(_wire(), memory);
    aim = release_pull("B", float(first["x"]), float(first["y"]), 800.0, 400.0, 1.0, True, False, False);
    assert aim.fired;
    assert float(first["x"]) >= 0.0 and float(first["x"]) <= 120.0;
    assert float(first["y"]) >= 300.0 and float(first["y"]) <= 399.0;
    for turn in range(3, 30, 2) {
        plan = json.loads(choose(_wire(turn, "combat"), memory));
        assert plan["weapon"] == "shell";
        assert release_pull("B", float(plan["x"]), float(plan["y"]), 800.0, 400.0, 1.0, True, False, False).fired;
    }
}

test "bot cannot fire on another seat turn or after the match" {
    data = json.loads(_wire());
    data["your_turn"] = False;
    assert not json.loads(choose(json.dumps(data), new_memory(1)))["ready"];
    data["your_turn"] = True;
    data["phase"] = "finished";
    assert not json.loads(choose(json.dumps(data), new_memory(1)))["ready"];
}

test "memory learns only live revealed positions and never hidden extras" {
    data = json.loads(_wire());
    data["reveal_until"] = 2000;
    data["view"]["reveal"] = {"bodies": [
        {"id": "private-core-id", "role": "core", "x": 30.61, "y": 4.05, "alive": True, "health": -1.0},
        {"id": "sentinel", "role": "marker", "x": 12345.67, "y": -9876.54, "alive": True}
    ]};
    data["hidden_secret"] = 87654.32;
    memory = learn(json.dumps(data), new_memory(1), 1999);
    parsed = json.loads(memory);
    assert len(parsed["targets"]) == 1;
    assert parsed["targets"][0]["x"] == 30.5;
    assert parsed["targets"][0]["y"] == 4.0;
    assert "private-core-id" not in memory;
    assert "health" not in memory;
    assert "87654.32" not in memory;
    assert "12345.67" not in memory;
    expired = learn(json.dumps(data), new_memory(1), 2000);
    assert len(json.loads(expired)["targets"]) == 0;
    assert learn(_wire(3, "combat"), memory, 3000) == memory;
    reset = learn(json.dumps({"epoch": 2, "view": {"reveal": None}}), memory, 3000);
    assert len(json.loads(reset)["targets"]) == 0;
}

test "unobserved fields do not affect a decision but remembered targets can" {
    wire = _wire(3, "combat");
    extra = json.loads(wire);
    extra["canonical"] = {"enemy_x": 87654.32, "health": 999, "secret_seed": 12345.67};
    assert choose(wire, new_memory(1)) == choose(json.dumps(extra), new_memory(1));
    data = json.loads(wire);
    data["reveal_until"] = 100;
    data["view"]["reveal"] = {"bodies": [{"role": "core", "x": 30.5, "y": 4.0, "alive": True}]};
    memory = learn(json.dumps(data), new_memory(1), 1);
    assert choose(wire, memory) != choose(wire, new_memory(1));
}

test "remembered targets stay bounded across many reveals" {
    data = json.loads(_wire());
    data["reveal_until"] = 100;
    memory = new_memory(1);
    for index in range(25) {
        data["view"]["reveal"] = {"bodies": [{"role": "post", "x": float(index), "y": 2.0, "alive": True}]};
        memory = learn(json.dumps(data), memory, 1);
    }
    assert len(json.loads(memory)["targets"]) <= 8;
}
