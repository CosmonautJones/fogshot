"""Phaser presentation of the visible field. The enemy half stays covered.

The scene callbacks live in mount_field.js because a Jac lambda does not receive
Phaser's scene as `this`. The shot drawn here stops at the midline. It is the
local guide, not a server hit.
"""

import from "react" { useEffect }
import from "./mount_field.js" { mountField }

def:pub Battlefield -> JsxElement {
    has caption: str = "Pull back from the launcher. The shot stops at the fog. A break still has to come from the server.";

    useEffect(lambda {
        parent = document.getElementById("fogshot-field");
        handle = mountField(parent) as any;
        return lambda {
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
