// Destruction playtest at 1280x800 desktop and 390x844 touch: a practice duel on a generated
// long ridge. Captures the ground before a blast, the burst, the crater after it, the bot's
// answer on our half, a long shell at the enemy half and the overview. Records crater/debris
// counts and the client frame rate (dataset.fps = game.loop.actualFps) through the duel.
// Shots are clipped to the arena and aim bar (no room code). Writes /tmp/fogshot-destruction/.
// Usage: FOGSHOT_PLAYWRIGHT=$PWD/.jac/e2e/node_modules/playwright node qa/destruction-playtest.mjs
import fs from "node:fs";
import {createRequire} from "node:module";
const require = createRequire(import.meta.url);
const {chromium} = require(process.env.FOGSHOT_PLAYWRIGHT || "playwright");
const base = process.env.FOGSHOT_URL || "http://127.0.0.1:8000/";
const out = "/tmp/fogshot-destruction/"; fs.mkdirSync(out, {recursive: true});
const browser = await chromium.launch({headless: true});
const ds = p => p.evaluate(() => ({...document.getElementById("fogshot-field").dataset}));
const until = (page, fn, arg, timeout = 20000) => page.waitForFunction(fn, arg, {timeout, polling: 50});
const report = {runs: []};
async function shot(page, vp, name, run) {
  const box = await page.evaluate(() => {
    const parts = [document.querySelector(".arena-frame"), document.querySelector("#fogshot-aimbar")].filter(Boolean).map(e => e.getBoundingClientRect());
    const x = Math.min(...parts.map(r => r.left)), y = Math.min(...parts.map(r => r.top));
    return {x: Math.max(0, x), y: Math.max(0, y), width: Math.max(...parts.map(r => r.right)) - x, height: Math.max(...parts.map(r => r.bottom)) - y};
  });
  const path = `${out}${vp.name}-${name}.png`;
  await page.screenshot({path, clip: box});
  const d = await ds(page);
  run.shots.push({name, path, camera: d.camera, craters: Number(d.craters), debris: Number(d.debris), fps: Number(d.fps), aim: [d.aimDegrees, d.aimPercent]});
}
async function drag(page, cdp, vp, dx, dy) {
  const b = await page.locator("#fogshot-field canvas").boundingBox();
  const sx = b.x + b.width * .6, sy = b.y + b.height * .5, ex = sx + dx * b.width / 800, ey = sy + dy * b.height / 400;
  if (vp.touch) {
    await cdp.send("Input.dispatchTouchEvent", {type: "touchStart", touchPoints: [{x: sx, y: sy}]});
    for (let i = 1; i <= 10; i++) await cdp.send("Input.dispatchTouchEvent", {type: "touchMove", touchPoints: [{x: sx + (ex - sx) * i / 10, y: sy + (ey - sy) * i / 10}]});
    await cdp.send("Input.dispatchTouchEvent", {type: "touchEnd", touchPoints: []});
  } else {
    await page.mouse.move(sx, sy); await page.mouse.down(); await page.mouse.move(ex, ey, {steps: 10}); await page.mouse.up();
  }
}
const ready = page => until(page, () => { const d = document.getElementById("fogshot-field").dataset; return (d.yourTurn === "true" || d.phase === "finished") && d.camera === "home" && d.botThinking !== "true"; }, null, 70000);
async function fire(page, run, weapon) {
  const fired = page.waitForResponse(r => r.request().method() === "POST" && r.url().includes("/function/loose_shot"));
  await page.locator("#fogshot-fire").click();
  const receipt = JSON.parse((await (await fired).json()).data.result);
  const far = receipt.path?.length ? receipt.path[receipt.path.length - 1] : null;
  run.flights.push({weapon, ok: receipt.ok, code: receipt.code, points: receipt.path?.length, end: far});
  return receipt;
}
async function sampleFps(page, run, ms) {
  const end = Date.now() + ms;
  while (Date.now() < end) { const d = await ds(page); if (d.fps) run.fps.push(Number(d.fps)); await page.waitForTimeout(400); }
}
for (const vp of [{name: "desktop", width: 1280, height: 800, touch: false}, {name: "mobile", width: 390, height: 844, touch: true}]) {
  const ctx = await browser.newContext({viewport: {width: vp.width, height: vp.height}, hasTouch: vp.touch, isMobile: vp.touch, deviceScaleFactor: vp.touch ? 2 : 1});
  const page = await ctx.newPage();
  const cdp = await ctx.newCDPSession(page);
  const run = {vp: vp.name, console: [], pageErrors: [], shots: [], flights: [], fps: []};
  page.on("console", m => { if (m.type() === "error") run.console.push(m.text().slice(0, 300)); });
  page.on("pageerror", e => run.pageErrors.push(String(e).slice(0, 300)));
  const url = new URL(base); url.searchParams.set("practice", "1");
  await page.goto(url.toString(), {waitUntil: "domcontentloaded"});
  await until(page, () => { const d = document.getElementById("fogshot-field")?.dataset; return d?.seat === "A" && d.yourTurn === "true" && d.fieldMode === "long"; }, null, 90000);
  await page.waitForTimeout(2600);
  const start = await ds(page);
  run.field = {w: Number(start.fieldW), ridge: start.ridge};
  // Recon: one flare (flares never carve).
  await drag(page, cdp, vp, -119, 119);
  await until(page, () => document.getElementById("fogshot-field").dataset.aimLocked === "true");
  await fire(page, run, "flare");
  await page.waitForTimeout(1500);
  await ready(page);
  await page.waitForTimeout(2500);
  run.afterFlares = Number((await ds(page)).craters);
  // A short, steep shell that lands on our own half, in view of home.
  await shot(page, vp, "1-before-blast", run);
  await drag(page, cdp, vp, -38, 92);
  await until(page, () => document.getElementById("fogshot-field").dataset.aimLocked === "true");
  await fire(page, run, "shell");
  await until(page, () => document.getElementById("fogshot-field").dataset.camera === "impact", null, 12000).catch(() => {});
  await page.waitForTimeout(120);
  await shot(page, vp, "2-blast", run);
  await page.waitForTimeout(1200);
  await shot(page, vp, "3-after-blast", run);
  await sampleFps(page, run, 4000);
  // The bot answers onto our half: its crater (and any fractured blocks) show on our side.
  await until(page, () => document.getElementById("fogshot-field").dataset.camera === "follow", null, 40000).catch(() => {});
  await until(page, () => document.getElementById("fogshot-field").dataset.camera === "impact", null, 15000).catch(() => {});
  await page.waitForTimeout(500);
  await shot(page, vp, "4-incoming-blast", run);
  await ready(page);
  await page.waitForTimeout(2600);
  await shot(page, vp, "5-home-after-exchange", run);
  // A long shell into the enemy half.
  await drag(page, cdp, vp, -119, 119);
  await until(page, () => document.getElementById("fogshot-field").dataset.aimLocked === "true");
  await fire(page, run, "shell");
  await until(page, () => document.getElementById("fogshot-field").dataset.camera === "impact", null, 15000).catch(() => {});
  await page.waitForTimeout(900);
  await shot(page, vp, "6-enemy-half-crater", run);
  await sampleFps(page, run, 3000);
  await ready(page).catch(() => {});
  await page.waitForTimeout(2600);
  const b = await page.locator("#fogshot-field canvas").boundingBox();
  const sx = b.x + b.width * .5, sy = b.y + b.height * (22 / 400);
  if (vp.touch) await page.touchscreen.tap(sx, sy); else await page.mouse.click(sx, sy);
  await page.waitForTimeout(900);
  await shot(page, vp, "7-overview", run);
  run.overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
  const fps = [...run.fps].sort((x, y) => x - y);
  run.fpsSummary = fps.length ? {min: fps[0], median: fps[Math.floor(fps.length / 2)], samples: fps.length} : null;
  report.runs.push(run);
  await ctx.close();
}
await browser.close();
report.summary = {errors: report.runs.reduce((s, r) => s + r.console.length + r.pageErrors.length, 0), overflow: report.runs.some(r => r.overflow), fps: report.runs.map(r => [r.vp, r.fpsSummary]), craters: report.runs.map(r => [r.vp, r.afterFlares, r.shots.map(s => s.craters)])};
fs.writeFileSync(`${out}destruction-report.json`, JSON.stringify(report, null, 2));
console.log(JSON.stringify(report.summary));
