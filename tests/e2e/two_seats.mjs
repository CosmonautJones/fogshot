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
    if (bodies.length < 1 || leaked.length) {
        fail(`seat B bodies ${bodies.length}, leaked ${leaked.length}`);
    }
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
