"""Phaser field driven by the shared match. The drawn shot is the server path."""

import from "react" { useEffect }
import from "@jac/runtime" { SignupResult, jacLogin, jacSignup }
import from "./mount_field.js" { mountField }
import from server.live { join_seat, loose_shot, watch_match }

glob INVITE: str = "fogshot";
glob PASSWORD: str = "fogshot-seat";
glob _set_caption: any = None;
glob _apply: any = None;
glob _timer: any = None;
glob _joined: bool = False;
glob _joining: bool = False;
glob _email_ready: str = "";

def _email() -> str {
    if _email_ready == "" {
        token = (crypto as any).randomUUID() as str;
        _email_ready = "fog-" + token + "@example.com";
    }
    return _email_ready;
}

def _command() -> str {
    token = (crypto as any).randomUUID() as str;
    return "cmd-" + str(Date.now()) + "-" + token;
}

def _note(raw: str) -> None {
    if not _set_caption {
        return;
    }
    parsed = JSON.parse(raw) as any;
    text = "Seat " + str(parsed.seat) + " / " + str(parsed.phase) + " / " + str(parsed.weapon) + ". Pull back from the launcher. The shot is the server result.";
    if parsed.code {
        text = text + " (" + str(parsed.code) + ")";
    }
    _set_caption.call(None, text);
}

async def _join() -> None {
    if _joining or _joined {
        return;
    }
    _joining = True;
    email = _email();
    signup_result: SignupResult | None = None;
    login_ok: bool = False;
    joined: str = "";
    signup_result = await jacSignup(email, PASSWORD);
    if not signup_result.success {
        _joining = False;
        if _set_caption {
            _set_caption.call(None, "Signup failed.");
        }
        return;
    }
    login_ok = await jacLogin(email, PASSWORD);
    if not login_ok {
        _joining = False;
        if _set_caption {
            _set_caption.call(None, "Login failed.");
        }
        return;
    }
    joined = await join_seat(INVITE);
    _joined = True;
    if _apply {
        _apply.call(None, joined);
    }
    _note(joined);
    if _timer is None {
        _timer = setInterval(lambda { _poll(); }, 700);
    }
}

async def _poll() -> None {
    if not _joined {
        return;
    }
    raw: str = "";
    try {
        raw = await watch_match(INVITE, int(Date.now()));
    } except Exception {
        return;
    }
    if _apply {
        _apply.call(None, raw);
    }
    _note(raw);
}

async def _release(px: float, py: float) -> None {
    if not _joined {
        return;
    }
    fired: str = "";
    try {
        fired = await loose_shot(INVITE, _command(), px, py, 800.0, 400.0, 1.0, int(Date.now()));
    } except Exception {
        if _set_caption {
            _set_caption.call(None, "The server rejected the pull.");
        }
        return;
    }
    if _apply {
        _apply.call(None, fired);
    }
    _note(fired);
}

def:pub Battlefield -> JsxElement {
    has caption: str = "Joining the match.";

    def remember(text: str) {
        caption = text;
    }

    useEffect(lambda {
        parent = document.getElementById("fogshot-field");
        handle = mountField(parent) as any;
        _set_caption = remember;
        _apply = lambda (raw: str) {
            handle.apply(raw);
        };
        (window as any).fogshotFire = lambda (px: float, py: float) {
            _release(px, py);
        };
        _join();
        return lambda {
            _joined = False;
            if _timer is not None {
                clearInterval(_timer);
                _timer = None;
            }
            (window as any).fogshotFire = None;
            _apply = None;
            _set_caption = None;
            handle.destroy();
        };
    }, []);

    <section style={{
        "fontFamily": "system-ui, sans-serif",
        "background": "#10141a",
        "color": "#e7eef2",
        "minHeight": "100vh",
        "padding": "1.5rem"
    }}>
        <h1 style={{"fontSize": "1.4rem", "margin": "0 0 0.4rem"}}>Fogshot</h1>
        <p>{caption}</p>
        <div id="fogshot-field" style={{"width": "800px", "height": "400px"}}></div>
    </section>
}
