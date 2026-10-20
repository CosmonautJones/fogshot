"""Fogshot boot. The page renders the battlefield. Rules stay on the server."""

import from client.battlefield { Battlefield }

def:pub app -> JsxElement {
    <Battlefield/>
}

# Retain the server boot artifact required by Jac 0.37.23 sealed apps.
with entry {}
