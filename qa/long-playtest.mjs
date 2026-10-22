// Long-range playtest at 1280x800 desktop and 390x844 touch: a practice duel on a generated
// long ridge, capturing the home view, a locked aim, the camera following a long flight, the
// burst, the bot's incoming shell, the minimap look at the enemy side and the return home.
// Shots are clipped to the arena and aim bar (no room code). Writes /tmp/fogshot-long/.
// Usage: FOGSHOT_PLAYWRIGHT=.jac/e2e/node_modules/playwright node qa/long-playtest.mjs
import fs from "node:fs";
import {createRequire} from "node:module";
const require = createRequire(import.meta.url);
const {chromium} = require(process.env.FOGSHOT_PLAYWRIGHT || "playwright");
const base = process.env.FOGSHOT_URL || "http://127.0.0.1:8000/";
const out = "/tmp/fogshot-long/"; fs.mkdirSync(out, {recursive: true});
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
  run.shots.push({name, path, camera: d.camera, cameraX: Number(d.cameraX), aim: [d.aimDegrees, d.aimPercent]});
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
for (const vp of [{name: "desktop", width: 1280, height: 800, touch: false}, {name: "mobile", width: 390, height: 844, touch: true}]) {
  const ctx = await browser.newContext({viewport: {width: vp.width, height: vp.height}, hasTouch: vp.touch, isMobile: vp.touch, deviceScaleFactor: vp.touch ? 2 : 1});
  const page = await ctx.newPage();
  const cdp = await ctx.newCDPSession(page);
  const run = {vp: vp.name, console: [], pageErrors: [], shots: [], flights: []};
  page.on("console", m => { if (m.type() === "error") run.console.push(m.text().slice(0, 300)); });
  page.on("pageerror", e => run.pageErrors.push(String(e).slice(0, 300)));
  const url = new URL(base); url.searchParams.set("practice", "1");
  await page.goto(url.toString(), {waitUntil: "domcontentloaded"});
  await until(page, () => { const d = document.getElementById("fogshot-field")?.dataset; return d?.seat === "A" && d.yourTurn === "true" && d.fieldMode === "long"; }, null, 90000);
  await page.waitForTimeout(2600);
  const start = await ds(page);
  run.field = {w: Number(start.fieldW), ridge: start.ridge, launcherX: Number(start.launcherX)};
  await shot(page, vp, "1-home", run);
  // Relative drag: 45 degrees at about 70% power, then nudge two degrees up.
  await drag(page, cdp, vp, -119, 119);
  await until(page, () => document.getElementById("fogshot-field").dataset.aimLocked === "true");
  for (let i = 0; i < 4; i++) await page.locator("[data-aim='angle-up']").click();
  await shot(page, vp, "2-aim", run);
  for (const weapon of ["flare", "shell"]) {
    await until(page, () => { const d = document.getElementById("fogshot-field").dataset; return (d.yourTurn === "true" || d.phase === "finished") && d.camera === "home" && d.botThinking !== "true"; }, null, 60000);
    if ((await ds(page)).phase === "finished") break;
    const fired = page.waitForResponse(r => r.request().method() === "POST" && r.url().includes("/function/loose_shot"));
    await page.locator("#fogshot-fire").click();
    const receipt = JSON.parse((await (await fired).json()).data.result);
    const far = receipt.path?.length ? Math.max(...receipt.path.map(p => p[0])) : null;
    run.flights.push({weapon, ok: receipt.ok, code: receipt.code, points: receipt.path?.length, farX: far, from: run.field.launcherX});
    if (weapon === "flare") {
      await until(page, () => document.getElementById("fogshot-field").dataset.camera === "follow", null, 6000);
      await page.waitForTimeout(500);
      await shot(page, vp, "3-follow-early", run);
      await until(page, w => Number(document.getElementById("fogshot-field").dataset.cameraX) > w * 20 * 0.4, run.field.w, 12000).catch(() => {});
      await shot(page, vp, "4-follow-far", run);
      await until(page, () => document.getElementById("fogshot-field").dataset.camera === "impact", null, 12000).catch(() => {});
      await page.waitForTimeout(250);
      await shot(page, vp, "5-burst-reveal", run);
      // The camera goes home, then the bot answers and the camera follows its incoming shell
      // (the defender only sees the part of the flight over its own half).
      await until(page, () => document.getElementById("fogshot-field").dataset.camera === "home", null, 8000).catch(() => {});
      await until(page, () => document.getElementById("fogshot-field").dataset.camera === "follow", null, 40000).catch(() => {});
      await page.waitForTimeout(350);
      await shot(page, vp, "6-incoming", run);
    } else {
      await until(page, () => document.getElementById("fogshot-field").dataset.camera === "follow", null, 6000);
      await page.waitForTimeout(1300);
      await shot(page, vp, "9-shell-flight", run);
    }
    // Let the exchange finish: our burst, home, the bot's incoming shell, home again, banner gone.
    await until(page, () => document.getElementById("fogshot-field").dataset.camera === "home", null, 12000).catch(() => {});
    if (weapon === "shell") await until(page, () => document.getElementById("fogshot-field").dataset.camera === "follow", null, 40000).catch(() => {});
    await until(page, () => { const d = document.getElementById("fogshot-field").dataset; return (d.yourTurn === "true" || d.phase === "finished") && d.camera === "home" && d.botThinking !== "true"; }, null, 60000).catch(() => {});
    await page.waitForTimeout(2800);
  }
  // Minimap: tap the far end of the strip to look at the enemy side.
  const b = await page.locator("#fogshot-field canvas").boundingBox();
  const sx = b.x + b.width * .7, sy = b.y + b.height * (22 / 400);
  if (vp.touch) await page.touchscreen.tap(sx, sy); else await page.mouse.click(sx, sy);
  await until(page, () => document.getElementById("fogshot-field").dataset.camera === "look", null, 5000).catch(() => {});
  await page.waitForTimeout(700);
  await shot(page, vp, "7-overview-look", run);
  await page.locator("[data-aim='home']").click();
  await until(page, () => document.getElementById("fogshot-field").dataset.camera === "home", null, 8000).catch(() => {});
  await page.waitForTimeout(900);
  await shot(page, vp, "8-home-again", run);
  run.overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
  report.runs.push(run);
  await ctx.close();
}
await browser.close();
report.summary = {errors: report.runs.reduce((s, r) => s + r.console.length + r.pageErrors.length, 0), overflow: report.runs.some(r => r.overflow), flights: report.runs.flatMap(r => r.flights)};
fs.writeFileSync(`${out}long-report.json`, JSON.stringify(report, null, 2));
console.log(JSON.stringify(report.summary));
