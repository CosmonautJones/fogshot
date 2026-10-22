"""Owner-only practice lifecycle, legal observations and durable bot turns."""
import json;
import tempfile;
import from pathlib { Path }
import from server.clock { pin_clock }
import from server.live { boot_match, boot_practice, practice_watch, take_shot, rematch_room, watch, open_practice, room_match, claim_player, _practice_code }
import from game.practice_bot { choose }

::py::
def _parallel(live, watcher):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier
    gate = Barrier(2)
    def call():
        gate.wait()
        return watcher(live, "human")
    with ThreadPoolExecutor(max_workers=2) as pool:
        return list(pool.map(lambda _: call(), range(2)))
def _publication_probe(opener, lookup, code_for, owner):
    import sys
    from concurrent.futures import ThreadPoolExecutor
    from threading import Event, current_thread
    module = sys.modules[opener.__module__]
    arm = module._arm
    entered, release = Event(), Event()
    creator = [None]
    code = code_for(owner, 0)
    def pause(live):
        if current_thread().ident == creator[0]:
            entered.set()
            assert release.wait(5), "publication test timed out"
        return arm(live)
    def create():
        creator[0] = current_thread().ident
        return opener(owner)
    module._arm = pause
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            future = pool.submit(create)
            # Long-range ridge generation can take several seconds before the room is armed.
            assert entered.wait(60), "creation did not reach initialization"
            observer = pool.submit(lookup, code)
            try:
                partial = observer.result(timeout=0.2)
                protected = partial is None or partial.practice is not None
            except TimeoutError:
                protected = True
            release.set()
            assert future.result(timeout=60) == code
            final = observer.result(timeout=5)
            return protected and (final is None or final.practice is not None)
    finally:
        release.set()
        module._arm = arm

def _failed_publication(opener, lookup, code_for, owner):
    import sys
    module = sys.modules[opener.__module__]
    save = module._save_canonical
    def fail(*args):
        raise OSError("initial snapshot interrupted")
    module._save_canonical = fail
    try:
        try:
            opener(owner)
        except OSError:
            pass
    finally:
        module._save_canonical = save
    return lookup(code_for(owner, 0)) is None
::py::

def _ready() -> any {
    pin_clock(1000);
    return boot_practice(tempfile.mkdtemp(prefix="fogshot-practice-"), "human", "aabbcc");
}
def _pull(live: any, x: float, y: float) -> any {
    return json.loads(take_shot(live, "human", "human-" + str(live.table.epoch) + "-" + str(live.table.turn),
        x, y, 800.0, 400.0, 1.0, live.table.epoch, live.table.turn, live.table.revision,
        "flare" if live.table.rules.phase == "recon" else "shell"));
}

test "practice reserves its bot and never exposes private practice state" {
    live = _ready();
    assert live.table.seat_a == "human";
    assert live.table.seat_b != "" and live.table.seat_b != "human";
    wire = practice_watch(live, "human");
    data = json.loads(wire);
    assert data["mode"] == "practice" and data["seat"] == "A" and data["your_turn"];
    assert live.table.seat_b not in wire;
    assert "memory" not in wire and "plan" not in wire and "owner" not in wire;
    assert not json.loads(practice_watch(live, "intruder"))["ok"];
    pin_clock(-1);
}

test "human reveal finishes before exactly one due bot move and restart retains it" {
    live = _ready();
    assert _pull(live, 20.0, 300.0)["ok"];
    due = int(live.practice["due"]);
    assert due > live.reveal_until;
    pin_clock(due - 1);
    assert json.loads(practice_watch(live, "human"))["turn"] == 1;
    resumed = boot_match(live.table.directory, "aabbcc");
    assert int(resumed.practice["due"]) == due;
    pin_clock(due);
    ready = json.loads(practice_watch(resumed, "human"));
    assert ready["turn"] == 2 and ready["your_turn"] and ready["phase"] == "combat";
    assert len(json.loads(str(resumed.practice["memory"]))["targets"]) > 0;
    again = json.loads(practice_watch(resumed, "human"));
    assert again["turn"] == 2;
    recovered = boot_match(live.table.directory, "aabbcc");
    assert json.loads(practice_watch(recovered, "human"))["turn"] == 2;
    assert recovered.table.shots == 2;
    pin_clock(-1);
}

test "failed bot commit preserves its exact plan and memory until retry" {
    live = _ready();
    assert _pull(live, 20.0, 300.0)["ok"];
    pin_clock(int(live.practice["due"]));
    live.table.fail_storage = True;
    practice_watch(live, "human");
    assert live.table.turn == 1 and live.table.shots == 1;
    plan = json.dumps(live.practice["plan"]);
    memory = str(live.practice["memory"]);
    assert plan != "null";
    assert len(json.loads(memory)["targets"]) == 0;
    assert json.loads(practice_watch(live, "human"))["turn"] == 2;
    assert live.table.shots == 2;
    assert live.practice["plan"] is None;
    pin_clock(-1);
}

test "changing unrevealed canonical enemies cannot change bot decisions" {
    live = _ready();
    assert _pull(live, 20.0, 300.0)["ok"];
    bot = str(live.practice["bot"]);
    before = watch(live, bot, 0);
    first = choose(before, str(live.practice["memory"]));
    for body in live.table.secrets {
        if body.owner == "A" {
            body.x = body.x + 2.75;
            body.health = 99.0;
        }
    }
    after = watch(live, bot, 0);
    assert before == after;
    assert choose(after, str(live.practice["memory"])) == first;
    pin_clock(-1);
}

test "human can win and practice rematch persists a fresh bot generation" {
    live = _ready();
    assert _pull(live, 20.0, 300.0)["ok"];
    pin_clock(int(live.practice["due"]));
    practice_watch(live, "human");
    won = _pull(live, 10.0, 390.0);
    assert won["result"] == "A";
    assert not json.loads(practice_watch(live, "human"))["bot_thinking"];
    epoch = live.table.epoch;
    fresh = json.loads(rematch_room(live, "human"));
    assert fresh["phase"] == "recon" and fresh["epoch"] == epoch + 1;
    assert int(live.practice["due"]) == 0 and live.practice["plan"] is None;
    assert len(json.loads(str(live.practice["memory"]))["targets"]) == 0;
    resumed = boot_match(live.table.directory, "aabbcc");
    assert resumed.practice is not None;
    assert json.loads(practice_watch(resumed, "human"))["epoch"] == epoch + 1;
    assert resumed.table.shots == 0;
    assert not json.loads(rematch_room(resumed, "human"))["ok"];
    pin_clock(-1);
}

test "bot can finish a match from its own scouting without hidden access" {
    live = _ready();
    assert _pull(live, 20.0, 300.0)["ok"];
    for index in range(12) {
        if live.table.rules.phase == "finished" { break; }
        if live.table.rules.active == "B" {
            pin_clock(int(live.practice["due"]));
            practice_watch(live, "human");
        } else {
            _pull(live, 20.0, 300.0);
        }
    }
    assert live.table.rules.result == "B";
    assert not json.loads(practice_watch(live, "human"))["bot_thinking"];
    shots = live.table.shots;
    practice_watch(live, "human");
    assert live.table.shots == shots;
    pin_clock(-1);
}

test "practice creation retries reuse the same owner room and exclude another player" {
    owner = tempfile.mkdtemp(prefix="practice-owner-");
    code = open_practice(owner);
    assert code != "" and len(code) == 6;
    assert open_practice(owner) == code;
    live = room_match(code);
    assert live.table.seat_a == owner;
    assert not claim_player(live, "intruder").ok;
    assert not json.loads(practice_watch(live, "intruder"))["ok"];
}

test "simultaneous due owner polls serialize one accepted bot command" {
    live = _ready();
    assert _pull(live, 20.0, 300.0)["ok"];
    pin_clock(int(live.practice["due"]));
    replies = _parallel(live, practice_watch) as list[str];
    assert live.table.shots == 2;
    for reply in replies {
        assert json.loads(reply)["turn"] == 2;
    }
    pin_clock(-1);
}


test "practice never publishes an unowned room during initialization" {
    owner = tempfile.mkdtemp(prefix="practice-publication-");
    assert _publication_probe(open_practice, room_match, _practice_code, owner);
}

test "interrupted initial practice snapshot leaves no joinable room" {
    owner = tempfile.mkdtemp(prefix="practice-interrupted-");
    assert _failed_publication(open_practice, room_match, _practice_code, owner);
}
