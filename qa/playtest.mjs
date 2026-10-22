// Scripted practice playtest: desktop + mobile, console errors, frame time, touch drag, rematch.
// Usage: FOGSHOT_PLAYWRIGHT=.jac/e2e/node_modules/playwright PREFIX=before node qa/playtest.mjs
import fs from "node:fs";
import {createRequire} from "node:module";
const require = createRequire(import.meta.url);
const {chromium} = require(process.env.FOGSHOT_PLAYWRIGHT || "playwright");
const url = (process.env.FOGSHOT_URL || "http://127.0.0.1:8000/") + "?practice=1";
const prefix = process.env.PREFIX || "before";
// The jac dev server full-reloads on any write in the repo, so capture to /tmp and copy at the end.
const dest = new URL(".", import.meta.url).pathname;
const out = "/tmp/fogshot-qa/"; fs.mkdirSync(out, {recursive: true});
const report = {prefix, runs: []};
const browser = await chromium.launch({headless: true});
const ds = p => p.evaluate(() => ({...document.getElementById("fogshot-field").dataset}));
async function frameStats(page, ms = 2500) {
  return page.evaluate(ms => new Promise(res => {
    const t = []; let last = performance.now(); const end = last + ms;
    const tick = now => { t.push(now - last); last = now; if (now < end) requestAnimationFrame(tick); else {
      t.sort((a, b) => a - b); res({frames: t.length, avg: +(t.reduce((a, b) => a + b, 0) / t.length).toFixed(2), p95: +t[Math.floor(t.length * .95)].toFixed(2), max: +t[t.length - 1].toFixed(2)}); } };
    requestAnimationFrame(tick);
  }), ms);
}
async function waitTurn(page, timeout = 25000) {
  await page.waitForFunction(() => { const d = document.getElementById("fogshot-field")?.dataset; return d && (d.yourTurn === "true" || d.phase === "finished"); }, null, {timeout});
}
async function drag(page, cdp, x, y, touch) {
  const b = await page.locator("#fogshot-field canvas").boundingBox();
  const sx = b.x + 120 * b.width / 800, sy = b.y + 300 * b.height / 400;
  const ex = b.x + x * b.width / 800, ey = b.y + y * b.height / 400;
  const resp = page.waitForResponse(r => r.url().includes("/function/loose_shot"), {timeout: 8000}).catch(() => null);
  if (touch) {
    await cdp.send("Input.dispatchTouchEvent", {type: "touchStart", touchPoints: [{x: sx, y: sy}]});
    for (let i = 1; i <= 8; i++) await cdp.send("Input.dispatchTouchEvent", {type: "touchMove", touchPoints: [{x: sx + (ex - sx) * i / 8, y: sy + (ey - sy) * i / 8}]});
    await page.waitForTimeout(60);
    return {resp, mid: async () => {}, end: () => cdp.send("Input.dispatchTouchEvent", {type: "touchEnd", touchPoints: []})};
  }
  await page.mouse.move(sx, sy); await page.mouse.down();
  await page.mouse.move(ex, ey, {steps: 8});
  return {resp, end: () => page.mouse.up()};
}
async function shoot(page, cdp, x, y, touch, shotName) {
  await waitTurn(page);
  if ((await ds(page)).phase === "finished") return null;
  const g = await drag(page, cdp, x, y, touch);
  if (shotName) await page.screenshot({path: `${out}${prefix}-${shotName}.png`});
  await g.end();
  const r = await g.resp;
  if (!r) return {ok: false, reason: "no loose_shot request"};
  const env = await r.json(); return JSON.parse(env.data.result);
}
for (const vp of [{name: "desktop", width: 1280, height: 800, touch: false}, {name: "mobile", width: 390, height: 844, touch: true}]) {
  const ctx = await browser.newContext({viewport: {width: vp.width, height: vp.height}, hasTouch: vp.touch, isMobile: vp.touch, deviceScaleFactor: vp.touch ? 2 : 1});
  const page = await ctx.newPage();
  const cdp = await ctx.newCDPSession(page);
  const run = {vp: vp.name, console: [], pageErrors: [], shots: [], results: [], notes: []};
  page.on("console", m => { if (["error", "warning"].includes(m.type())) run.console.push(m.type() + ": " + m.text().slice(0, 300)); });
  page.on("pageerror", e => run.pageErrors.push(String(e).slice(0, 300)));
  const t0 = Date.now();
  await page.goto(url, {waitUntil: "domcontentloaded"});
  await page.waitForFunction(() => document.getElementById("fogshot-field")?.dataset.seat === "A", null, {timeout: 40000});
  run.timeToReadyMs = Date.now() - t0;
  await page.waitForTimeout(400);
  await page.screenshot({path: `${out}${prefix}-${vp.name}-start.png`});
  run.idleFrames = await frameStats(page);
  run.overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
  run.fieldBox = await page.locator("#fogshot-field canvas").boundingBox();
  // Round 1: flare, then shells with varied pulls until a result or cap.
  const pulls = [[20, 300], [10, 390], [30, 330], [5, 360], [40, 380], [15, 395], [0, 340], [25, 399]];
  for (let round = 0; round < 2; round++) {
    let n = 0;
    for (const [x, y] of pulls) {
      const r = await shoot(page, cdp, x, y, vp.touch, round === 0 && n === 0 ? `${vp.name}-aim` : "");
      n++;
      if (!r) break;
      run.shots.push({round, x, y, ok: r.ok, code: r.code || "", turn: r.turn, phase: r.phase, result: r.result || ""});
      if (round === 0 && n === 1) { await page.waitForTimeout(350); run.flightFrames = await frameStats(page, 1500); await page.screenshot({path: `${out}${prefix}-${vp.name}-reveal.png`}); }
      if (r.result) break;
      // wait for bot to answer
      await waitTurn(page, 30000).catch(() => run.notes.push("bot never returned turn"));
      if ((await ds(page)).phase === "finished") break;
    }
    const d = await ds(page);
    run.results.push({round, phase: d.phase, result: d.result, turnNumber: d.turnNumber, hud: await page.locator("#fogshot-turn").innerText()});
    await page.screenshot({path: `${out}${prefix}-${vp.name}-round${round}-end.png`});
    // Rematch
    const btn = page.getByRole("button", {name: "Rematch", exact: true});
    if (await btn.isEnabled()) { const e = Number(d.epoch); const tr = Date.now(); await btn.click();
      await page.waitForFunction(e => Number(document.getElementById("fogshot-field").dataset.epoch) > e && document.getElementById("fogshot-field").dataset.yourTurn === "true", e, {timeout: 15000}).catch(() => run.notes.push("rematch stuck"));
      run.rematchMs = Date.now() - tr; }
    else run.notes.push(`round ${round} not finished (phase ${d.phase}); rematch disabled`);
  }
  // Loss round: flare, then a flat shell that stops short; the bot then wins. Retry with the R key.
  if (vp.name === "desktop") {
    await shoot(page, cdp, 20, 300, false, "");
    await waitTurn(page, 30000);
    await shoot(page, cdp, 20, 300, false, "");
    await page.waitForFunction(() => document.getElementById("fogshot-field").dataset.phase === "finished", null, {timeout: 30000}).catch(() => run.notes.push("loss round never finished"));
    await page.waitForTimeout(700);
    run.loss = {result: (await ds(page)).result, hud: await page.locator("#fogshot-turn").innerText()};
    await page.screenshot({path: `${out}${prefix}-desktop-loss.png`});
    const e = Number((await ds(page)).epoch);
    await page.locator("body").click({position: {x: 5, y: 5}});
    await page.keyboard.press("r");
    run.rKeyRematch = await page.waitForFunction(e => Number(document.getElementById("fogshot-field").dataset.epoch) > e, e, {timeout: 5000}).then(() => true, () => false);
    await page.waitForTimeout(500);
    await page.screenshot({path: `${out}${prefix}-desktop-rematch.png`});
  }
  // resize mid-match
  await page.setViewportSize({width: vp.width === 1280 ? 700 : 844, height: vp.width === 1280 ? 800 : 390});
  await page.waitForTimeout(400);
  run.resizedBox = await page.locator("#fogshot-field canvas").boundingBox();
  await page.screenshot({path: `${out}${prefix}-${vp.name}-resized.png`});
  run.resizedOverflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
  report.runs.push(run);
  await ctx.close();
}
await browser.close();
for (const f of fs.readdirSync(out)) if (f.startsWith(prefix + "-")) fs.copyFileSync(out + f, dest + f);
fs.writeFileSync(`${dest}${prefix}-report.json`, JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
