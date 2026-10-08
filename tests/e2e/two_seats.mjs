// Two real browser contexts against a running jac dev server.
// This file does not stub the match. FOGSHOT_URL defaults to localhost:8000.
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.FOGSHOT_PLAYWRIGHT || "playwright");

const url = process.env.FOGSHOT_URL || "http://127.0.0.1:8000/";
const sentinels = ["12345.67", "-9876.54", "87654.32"];

function fail(message) {
    console.error(message);
    process.exitCode = 1;
}

async function read(page) {
    return page.evaluate(() => {
        const field = document.getElementById("fogshot-field");
        return {
            cap: document.querySelector("p")?.textContent || "",
            seat: field?.dataset.seat || "",
            turn: field?.dataset.yourTurn || "",
            rev: field?.dataset.reveal || "",
            br: field?.dataset.broken || "",
            ang: field?.dataset.postAngle || "",
            sx: field?.dataset.shotScreenX || "",
            st: field?.dataset.shotTime || "",
            pow: field?.dataset.powered || "",
            phase: field?.dataset.phase || "",
            result: field?.dataset.result || "",
            epoch: field?.dataset.epoch || "",
            ready: field?.dataset.shotReady || "",
        };
    });
}

async function pull(page, x, y) {
    await page.waitForFunction(
        () => document.getElementById("fogshot-field")?.dataset.yourTurn === "true",
        null,
        { timeout: 20000 },
    );
    const box = await page.locator("#fogshot-field canvas").boundingBox();
    if (!box) {
        throw new Error("the field canvas is missing");
    }
    const seat = await page.evaluate(() => document.getElementById("fogshot-field").dataset.seat);
    await page.mouse.move(box.x + (seat === "B" ? 680 : 120), box.y + 300);
    await page.mouse.down();
    await page.mouse.move(box.x + x, box.y + y, { steps: 6 });
    await page.mouse.up();
}

const browser = await chromium.launch({
    headless: true,
    channel: process.env.FOGSHOT_BROWSER_CHANNEL || undefined,
});
const ctxA = await browser.newContext({ viewport: { width: 960, height: 720 } });
const ctxB = await browser.newContext({ viewport: { width: 960, height: 720 } });
const a = await ctxA.newPage();
const b = await ctxB.newPage();
const bodies = [];
const ownBodies = [];
const shots = [];
for (const page of [a, b]) {
    page.on("request", (req) => {
        if (req.method() === "POST" && req.url().includes("/function/loose_shot")) {
            shots.push({
                url: req.url(),
                headers: req.headers(),
                body: req.postData() || "",
            });
        }
    });
}
a.on("response", async (res) => {
    try {
        if (res.url().includes("/function/")) {
            ownBodies.push(await res.text());
        }
    } catch (err) {
        ownBodies.push("");
    }
});
b.on("response", async (res) => {
    try {
        if (!res.url().includes("/function/")) {
            return;
        }
        bodies.push(await res.text());
    } catch (err) {
        bodies.push("");
    }
});

try {
    await a.goto(url, { waitUntil: "domcontentloaded" });
    await a.waitForFunction(
        () => document.getElementById("fogshot-field")?.dataset.seat === "A",
        null,
        { timeout: 20000 },
    );
    await b.goto(url, { waitUntil: "domcontentloaded" });
    await b.waitForFunction(
        () => document.getElementById("fogshot-field")?.dataset.seat === "B",
        null,
        { timeout: 20000 },
    );
    await pull(a, 20, 300);
    await pull(b, 60, 300);
    await a.waitForFunction(
        () => document.getElementById("fogshot-field")?.dataset.phase === "combat"
            && document.getElementById("fogshot-field")?.dataset.yourTurn === "true",
        null,
        { timeout: 20000 },
    );
    await pull(a, 20, 300);
    await a.waitForFunction(
        () => document.getElementById("fogshot-field")?.dataset.broken === "true",
        null,
        { timeout: 15000 },
    );
    await b.waitForFunction(
        () => document.getElementById("fogshot-field")?.dataset.powered === "false",
        null,
        { timeout: 15000 },
    );
    await a.waitForFunction(
        () => document.getElementById("fogshot-field")?.dataset.reveal === "closed",
        null,
        { timeout: 8000 },
    );
    await a.waitForTimeout(600);
    const closedA = await read(a);
    const closedB = await read(b);
    await a.waitForTimeout(400);
    const laterA = await read(a);
    console.log(JSON.stringify({ closedA, closedB, laterA, bodies: bodies.length }));
    if (closedA.rev !== "closed" || closedA.br !== "false" || closedA.sx !== "" || laterA.sx !== "") {
        fail(`seat A kept a shot or a break after the reveal closed: ${JSON.stringify({ closedA, laterA })}`);
    }
    if (!closedA.cap.includes("shell waiting")) {
        fail(`seat A caption did not say waiting: ${closedA.cap}`);
    }
    if (closedB.pow !== "false" || closedB.br !== "true" || !closedB.cap.includes("supply dark")) {
        fail(`seat B did not show the broken supply: ${JSON.stringify(closedB)}`);
    }
    if (closedB.sx !== "") {
        fail(`seat B still had a shot marker: ${closedB.sx}`);
    }
    const leaked = bodies.filter((text) => sentinels.some((item) => text.includes(item)));
    const ownLeaked = ownBodies.filter((text) => sentinels.some((item) => text.includes(item)));
    if (bodies.length < 1 || leaked.length || ownLeaked.length) {
        fail(`seat B bodies ${bodies.length}, leaked ${leaked.length}; seat A leaked ${ownLeaked.length}`);
    }
    await pull(b, 60, 300);
    await a.waitForFunction(
        () => document.getElementById("fogshot-field")?.dataset.yourTurn === "true",
        null,
        { timeout: 20000 },
    );
    await pull(a, 10, 390);
    await a.waitForFunction(
        () => document.getElementById("fogshot-field")?.dataset.phase === "finished"
            && document.getElementById("fogshot-field")?.dataset.result === "A",
        null,
        { timeout: 20000 },
    );
    await b.waitForFunction(
        () => document.getElementById("fogshot-field")?.dataset.phase === "finished"
            && document.getElementById("fogshot-field")?.dataset.result === "A",
        null,
        { timeout: 20000 },
    );
    const wonA = await read(a);
    const wonB = await read(b);
    if (!wonA.cap.includes("Result A") || !wonB.cap.includes("Result A") || wonA.ready !== "false" || wonB.ready !== "false") {
        fail(`victory state did not reach both seats: ${JSON.stringify({ wonA, wonB })}`);
    }
    const generation = wonA.epoch;
    await b.getByRole("button", { name: "Rematch" }).click();
    await a.waitForFunction(
        () => document.getElementById("fogshot-field")?.dataset.phase === "recon"
            && document.getElementById("fogshot-field")?.dataset.result === "",
        null,
        { timeout: 15000 },
    );
    await b.waitForFunction(
        (previous) => {
            const field = document.getElementById("fogshot-field");
            return field?.dataset.phase === "recon" && field?.dataset.epoch !== previous;
        },
        generation,
        { timeout: 15000 },
    );
    const nextA = await read(a);
    const nextB = await read(b);
    if (nextA.phase !== "recon" || nextB.phase !== "recon" || nextA.result || nextB.result) {
        fail(`rematch did not start a fresh generation: ${JSON.stringify({ nextA, nextB, generation })}`);
    }
    if (!(Number(nextA.epoch) > Number(generation)) || nextA.epoch !== nextB.epoch) {
        fail(`epoch did not advance together: ${JSON.stringify({ nextA, nextB, generation })}`);
    }
    const stale = shots[shots.length - 1];
    if (!stale) {
        fail("no shot request was captured");
    }
    const replay = await a.request.fetch(stale.url, {
        method: "POST",
        headers: {
            authorization: stale.headers.authorization,
            "content-type": stale.headers["content-type"] || "application/json",
        },
        data: stale.body,
    });
    const replayText = await replay.text();
    let replayCode = "";
    try {
        const wrapped = JSON.parse(replayText);
        const inner = JSON.parse(wrapped.data.result);
        replayCode = inner.code || "";
    } catch (parseErr) {
        replayCode = "";
    }
    await a.waitForTimeout(400);
    const after = await read(a);
    if (replayCode !== "epoch" || after.phase !== "recon" || after.epoch !== nextA.epoch) {
        fail(`stale command was not rejected: ${replayCode} ${replayText.slice(0, 500)} ${JSON.stringify(after)}`);
    }
    await pull(a, 20, 300);
    await pull(b, 60, 300);
    await a.waitForFunction(
        () => document.getElementById("fogshot-field")?.dataset.phase === "combat"
            && document.getElementById("fogshot-field")?.dataset.yourTurn === "true",
        null,
        { timeout: 20000 },
    );
    await pull(a, 20, 300);
    await b.waitForFunction(
        () => document.getElementById("fogshot-field")?.dataset.yourTurn === "true",
        null,
        { timeout: 20000 },
    );
    await pull(b, 20, 390);
    await b.waitForFunction(
        () => document.getElementById("fogshot-field")?.dataset.phase === "finished"
            && document.getElementById("fogshot-field")?.dataset.result === "B",
        null,
        { timeout: 20000 },
    );
    await a.waitForFunction(
        () => document.getElementById("fogshot-field")?.dataset.phase === "finished"
            && document.getElementById("fogshot-field")?.dataset.result === "B",
        null,
        { timeout: 20000 },
    );
    const beatA = await read(a);
    const beatB = await read(b);
    if (!beatA.cap.includes("Result B") || !beatB.cap.includes("Result B") || beatA.ready !== "false" || beatB.ready !== "false") {
        fail(`seat B's win did not reach both seats: ${JSON.stringify({ beatA, beatB })}`);
    }
    const beaten = beatB.epoch;
    await a.getByRole("button", { name: "Rematch" }).click();
    await b.waitForFunction(
        (previous) => {
            const field = document.getElementById("fogshot-field");
            return field?.dataset.phase === "recon" && field?.dataset.result === "" && field?.dataset.epoch !== previous;
        },
        beaten,
        { timeout: 15000 },
    );
    await a.waitForFunction(
        () => document.getElementById("fogshot-field")?.dataset.phase === "recon"
            && document.getElementById("fogshot-field")?.dataset.result === "",
        null,
        { timeout: 15000 },
    );
    const freshA = await read(a);
    const freshB = await read(b);
    if (freshA.epoch !== freshB.epoch || !(Number(freshA.epoch) > Number(beaten)) || freshA.result || freshB.result) {
        fail(`rematch after B's win did not start a new generation: ${JSON.stringify({ freshA, freshB, beaten })}`);
    }
    console.log(JSON.stringify({
        wonA: { phase: wonA.phase, result: wonA.result, epoch: wonA.epoch },
        wonB: { phase: wonB.phase, result: wonB.result },
        beatA: { phase: beatA.phase, result: beatA.result },
        beatB: { phase: beatB.phase, result: beatB.result, epoch: beatB.epoch },
        freshA: { phase: freshA.phase, epoch: freshA.epoch },
        freshB: { phase: freshB.phase, epoch: freshB.epoch },
    }));
} catch (err) {
    try {
        console.error(JSON.stringify({ a: await read(a), b: await read(b) }));
    } catch (readErr) {
        console.error(String(readErr));
    }
    fail(err && err.stack ? err.stack : String(err));
} finally {
    await browser.close();
}

if (process.exitCode) {
    process.exit(process.exitCode);
}
console.log("two seats ok");
