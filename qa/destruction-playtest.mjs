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
const out = "/tmp/fogshot-destruction/";
const roomRoot = (process.env.FOGSHOT_ROOM_ROOT || "/tmp/fogshot-dev-rooms") + "/"; fs.mkdirSync(out, {recursive: true});
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
async function fire(page, run, weapon, pointer = null) {
  const fired = page.waitForResponse(r => r.request().method() === "POST" && r.url().includes("/function/loose_shot"));
  // An exact protocol pointer goes through the page's own fire hook (the FIRE button's path).
  if (pointer) await page.evaluate(([x, y]) => window.fogshotFire(x, y), pointer);
  else await page.locator("#fogshot-fire").click();
  const receipt = JSON.parse((await (await fired).json()).data.result);
  const far = receipt.path?.length ? receipt.path[receipt.path.length - 1] : null;
  run.flights.push({weapon, ok: receipt.ok, code: receipt.code, points: receipt.path?.length, end: far});
  return receipt;
}
async function sampleFps(page, run, ms) {
  const end = Date.now() + ms;
  while (Date.now() < end) { const d = await ds(page); if (d.fps) run.fps.push(Number(d.fps)); await page.waitForTimeout(400); }
}
// Mirror of client previewArc's flight model: where is the shell when it reaches world x = tx?
function heightAt(angle, power, from, tx, field) {
  let x = from.x, y = from.y, vx = Math.cos(angle) * power, vy = Math.sin(angle) * power;
  const step = 1 / 60, keep = Math.pow(field.drag, step);
  for (let n = 0; n < 1200; n++) { vx *= keep; vy = vy * keep - field.gravity * step; x += vx * step; y += vy * step; if ((vx > 0 && x >= tx) || (vx < 0 && x <= tx)) return vy < 0 ? y : null; }
  return null;
}
// Power (m/s) at 62 degrees that brings the shell down onto (tx, ty).
function solvePower(from, tx, ty, field) {
  let lo = 4, hi = field.v_max;
  for (let i = 0; i < 40; i++) { const mid = (lo + hi) / 2; const y = heightAt(62 * Math.PI / 180, mid, from, tx, field); if (y !== null && y < ty) lo = mid; else hi = mid; }
  return (lo + hi) / 2;
}
// Move the locked pad pull to (deg, pct) with one relative drag.
async function aimTo(page, cdp, vp, deg, pct) {
  const d = await ds(page);
  const cur = Number(d.aimDegrees) * Math.PI / 180, cp = Number(d.aimPercent) / 100 * 240;
  const t = deg * Math.PI / 180, tp = pct / 100 * 240;
  const dx = -(Math.cos(t) * tp - Math.cos(cur) * cp), dy = Math.sin(t) * tp - Math.sin(cur) * cp;
  await drag(page, cdp, vp, dx, dy);
  await page.waitForTimeout(300);
}
for (const vp of [{name: "desktop", width: 1280, height: 800, touch: false, ridge: 3003}, {name: "mobile", width: 390, height: 844, touch: true, ridge: 1001}]) {
  const ctx = await browser.newContext({viewport: {width: vp.width, height: vp.height}, hasTouch: vp.touch, isMobile: vp.touch, deviceScaleFactor: vp.touch ? 2 : 1});
  const page = await ctx.newPage();
  const cdp = await ctx.newCDPSession(page);
  const run = {vp: vp.name, console: [], pageErrors: [], shots: [], flights: [], fps: []};
  page.on("console", m => { if (m.type() === "error") run.console.push(m.text().slice(0, 300)); });
  page.on("pageerror", e => run.pageErrors.push(String(e).slice(0, 300)));
  let latest = null;
  page.on("response", async r => {
    if (!r.url().includes("/function/watch_match")) return;
    try { const body = await r.json(); const data = JSON.parse(body.data.result); if (data && data.view) latest = data; } catch {}
  });
  const url = new URL(base); url.searchParams.set("practice", "1");
  // Public ridges whose proof shell visibly fractures the enemy roof (see destruction_tests).
  if (vp.ridge) url.searchParams.set("ridge", String(vp.ridge));
  await page.goto(url.toString(), {waitUntil: "domcontentloaded"});
  await until(page, () => { const d = document.getElementById("fogshot-field")?.dataset; return d?.seat === "A" && d.yourTurn === "true" && d.fieldMode === "long"; }, null, 90000);
  await page.waitForTimeout(2600);
  const start = await ds(page);
  run.field = {w: Number(start.fieldW), ridge: start.ridge};
  // Recon: one flare each (flares never carve).
  async function recon() {
    await drag(page, cdp, vp, -119, 119);
    await until(page, () => document.getElementById("fogshot-field").dataset.aimLocked === "true");
    await fire(page, run, "flare");
    await until(page, () => document.getElementById("fogshot-field").dataset.yourTurn === "false", null, 10000).catch(() => {});
    await ready(page);
    await page.waitForTimeout(2500);
  }
  await recon();
  run.afterFlares = Number((await ds(page)).craters);
  // A steep shell onto open ground 18 m in front of our launcher, in view of home.
  const own = (latest && latest.view && latest.view.own) || [];
  const launcher = own.find(b => b.role === "launcher");
  const field = latest.field;
  // Open ground 8-30 m ahead, as far as possible from our own outpost.
  const keep = own.filter(b => !["launcher", "marker"].includes(b.role));
  let tx = launcher.x + 14, best = -1;
  for (let d = 8; d <= 30; d += 1) { const x = launcher.x + d; const gap = Math.min(...keep.map(b => Math.abs(b.x - x)), 99); if (gap > best) { best = gap; tx = x; } }
  const terrain = latest.terrain || [];
  let ty = 0;
  for (let i = 1; i < terrain.length; i++) if (terrain[i][0] >= tx) { const [x0, y0] = terrain[i - 1], [x1, y1] = terrain[i]; ty = y0 + (y1 - y0) * (tx - x0) / (x1 - x0); break; }
  const power = solvePower(launcher, tx, ty, field);
  // Let the bot's flare playback finish: the camera must sit at home for a moment.
  for (let i = 0; i < 40; i++) { await page.waitForTimeout(400); const d = await ds(page); if (d.camera === "home") { await page.waitForTimeout(1200); if ((await ds(page)).camera === "home") break; } }
  run.target = {dx: Math.round(tx - launcher.x), clear: best, ground: Math.round(ty * 10) / 10, power: Math.round(power * 10) / 10};
  await aimTo(page, cdp, vp, 62, power / field.v_max * 100);
  await shot(page, vp, "1-before-blast", run);
  await fire(page, run, "shell");
  await until(page, () => document.getElementById("fogshot-field").dataset.camera === "follow", null, 6000).catch(() => {});
  const mid = await ds(page);
  run.midFlight = {sent: Number(mid.craters), shown: Number(mid.cratersShown)};
  await until(page, () => document.getElementById("fogshot-field").dataset.camera === "impact", null, 12000).catch(() => {});
  await page.waitForTimeout(120);
  await shot(page, vp, "2-blast", run);
  await page.waitForTimeout(1600);
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
  // If the bot already won, rematch (fresh ridge, no craters) and scout again.
  if ((await ds(page)).phase === "finished") {
    const epoch = (await ds(page)).epoch;
    await page.keyboard.press("r");
    await until(page, e => { const d = document.getElementById("fogshot-field").dataset; return d.epoch !== e && d.yourTurn === "true" && d.phase === "recon"; }, epoch, 90000);
    await page.waitForTimeout(2600);
    run.rematch = {craters: Number((await ds(page)).craters)};
    await recon();
  }
  // The generator's proof pull for seat A (QA reads it from the dev room's layout file; the
  // game never sends it): the shell bursts on the enemy outpost, which fractures into debris.
  const room = (await ds(page)).room;
  const layout = JSON.parse(fs.readFileSync(`${roomRoot}${room}/layout.json`, "utf8")).layout;
  const proof = layout.proof.A;
  const pad = {x: field.pad_x - proof[0], y: proof[1] - field.pad_y};
  run.proof = {deg: Math.round(Math.atan2(pad.y, pad.x) * 1800 / Math.PI) / 10, pct: Math.round(Math.hypot(pad.x, pad.y) / field.full_pull * 1000) / 10};
  await fire(page, run, "shell", proof);
  await until(page, () => document.getElementById("fogshot-field").dataset.camera === "impact", null, 15000).catch(() => {});
  await page.waitForTimeout(250);
  await shot(page, vp, "6-outpost-hit", run);
  await page.waitForTimeout(1300);
  await shot(page, vp, "6b-outpost-debris", run);
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
