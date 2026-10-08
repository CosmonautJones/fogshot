import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

test("the browser does not share one password or one invite", () => {
    const source = fs.readFileSync(new URL("../client/battlefield.jac", import.meta.url), "utf8");
    assert.equal(source.includes("fogshot-seat"), false);
    assert.equal(source.includes("glob INVITE"), false);
    assert.equal(source.includes("create_room"), true);
});
