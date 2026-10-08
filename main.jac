"""Fogshot boot. The page renders the battlefield. Rules stay on the server."""

import from client.battlefield { Battlefield }

def:pub app -> JsxElement {
    <Battlefield/>
}
