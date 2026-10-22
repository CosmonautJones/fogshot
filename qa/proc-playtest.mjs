// Procedural-duel playtest: generated ridges, practice rematches at desktop and mobile sizes,
// whether the old scripted flare+lob still wins, and console errors.
// Usage: FOGSHOT_PLAYWRIGHT=.jac/e2e/node_modules/playwright node qa/proc-playtest.mjs
import fs from "node:fs";
import {createRequire} from "node:module";
const require = createRequire(import.meta.url);
const {chromium} = require(process.env.FOGSHOT_PLAYWRIGHT || "playwright");
const base = process.env.FOGSHOT_URL || "http://127.0.0.1:8000/";
// The jac dev server reloads on repo writes, so capture to /tmp; qa/proc-layouts.py composes the sheet.
const out = "/tmp/fogshot-proc/"; fs.mkdirSync(out, {recursive: true});
const ridges = (process.env.RIDGES || "48213,7,1312,25000,777,90210").split(",").map(Number);
const duels = {desktop: Number(process.env.DESKTOP_DUELS || 5), mobile: Number(process.env.MOBILE_DUELS || 3)};
const report = {ridges: [], runs: []};
const browser = await chromium.launch({headless: true});
const ds = p => p.evaluate(() => ({...document.getElementById("fogshot-field").dataset}));
const watchErrors = (page, run) => {
  page.on("console", m => { if (["error", "warning"].includes(m.type())) run.console.push(m.type() + ": " + m.text().slice(0, 300)); });
  page.on("pageerror", e => run.pageErrors.push(String(e).slice(0, 300)));
};
async function waitTurn(page, timeout = 30000) {
  await page.waitForFunction(() => { const d = document.getElementById("fogshot-field")?.dataset; return d && (d.yourTurn === "true" || d.phase === "finished"); }, null, {timeout});
}
async function shoot(page, cdp, x, y, touch) {
  await waitTurn(page);
  if ((await ds(page)).phase === "finished") return null;
  const b = await page.locator("#fogshot-field canvas").boundingBox();
  const d = await ds(page);
  const lx = Number(d.launcherX || 6) * 20, ly = (1 - Number(d.launcherY || 4) / 16) * 400;
  const sx = b.x + lx * b.width / 800, sy = b.y + ly * b.height / 400;
  const ex = b.x + x * b.width / 800, ey = b.y + y * b.height / 400;
  const resp = page.waitForResponse(r => r.url().includes("/function/loose_shot"), {timeout: 8000}).catch(() => null);
  if (touch) {
    await cdp.send("Input.dispatchTouchEvent", {type: "touchStart", touchPoints: [{x: sx, y: sy}]});
    for (let i = 1; i <= 8; i++) await cdp.send("Input.dispatchTouchEvent", {type: "touchMove", touchPoints: [{x: sx + (ex - sx) * i / 8, y: sy + (ey - sy) * i / 8}]});
    await page.waitForTimeout(60);
    await cdp.send("Input.dispatchTouchEvent", {type: "touchEnd", touchPoints: []});
  } else {
    await page.mouse.move(sx, sy); await page.mouse.down();
    await page.mouse.move(ex, ey, {steps: 8}); await page.mouse.up();
  }
  const r = await resp;
  if (!r) return {ok: false, code: "no request"};
  return JSON.parse((await r.json()).data.result);
}

// 1) Contact sheet: one fresh multiplayer room per shared ridge link, seat A's view.
{
  const ctx = await browser.newContext({viewport: {width: 1280, height: 800}});
  const page = await ctx.newPage();
  const run = {vp: "layouts", console: [], pageErrors: []};
  watchErrors(page, run);
  for (const ridge of ridges) {
    const url = new URL(base); url.searchParams.set("ridge", String(ridge));
    await page.goto(url.toString(), {waitUntil: "domcontentloaded"});
    // A ridge with no fair layout hands over to a deterministic fallback ridge, so accept any generated one.
    await page.waitForFunction(() => { const d = document.getElementById("fogshot-field")?.dataset; return d?.seat === "A" && Number(d.ridge) > 0 && d.room && new URLSearchParams(location.search).get("room") === d.room; }, null, {timeout: 60000});
    await page.waitForTimeout(2800); // let the turn banner fade
    await page.locator("#fogshot-field canvas").screenshot({path: `${out}ridge-${ridge}.png`});
    const d = await ds(page);
    report.ridges.push({ridge, shown: Number(d.ridge), label: await page.locator("#fogshot-ridge").innerText(), launcher: [Number(d.launcherX), Number(d.launcherY)]});
  }
  report.runs.push(run);
  await ctx.close();
}

// 2) Practice rematches. Each duel opens with the old scripted flare (20,300) + lob (10,390).
const followups = [[30, 330], [5, 360], [40, 380], [15, 395], [0, 340], [25, 399], [12, 320], [35, 350], [8, 380], [22, 370]];
for (const vp of [{name: "desktop", width: 1280, height: 800, touch: false}, {name: "mobile", width: 390, height: 844, touch: true}]) {
  const ctx = await browser.newContext({viewport: {width: vp.width, height: vp.height}, hasTouch: vp.touch, isMobile: vp.touch, deviceScaleFactor: vp.touch ? 2 : 1});
  const page = await ctx.newPage();
  const cdp = await ctx.newCDPSession(page);
  const run = {vp: vp.name, console: [], pageErrors: [], duels: [], overflow: false};
  watchErrors(page, run);
  const url = new URL(base); url.searchParams.set("practice", "1");
  await page.goto(url.toString(), {waitUntil: "domcontentloaded"});
  await page.waitForFunction(() => document.getElementById("fogshot-field")?.dataset.seat === "A", null, {timeout: 60000});
  for (let n = 1; n <= duels[vp.name]; n++) {
    await page.waitForFunction(() => { const d = document.getElementById("fogshot-field").dataset; return d.phase === "recon" && d.turnNumber === "0"; }, null, {timeout: 20000});
    await page.waitForTimeout(500);
    const start = await ds(page);
    const duel = {n, ridge: start.ridge, label: await page.locator("#fogshot-ridge").innerText(), botLevel: start.botLevel, scriptedWin: false, shots: 0, result: ""};
    if (n <= 3) await page.screenshot({path: `${out}${vp.name}-duel${n}-start.png`});
    const flare = await shoot(page, cdp, 20, 300, vp.touch);
    duel.shots++;
    if (n === 1) { await page.waitForTimeout(450); await page.screenshot({path: `${out}${vp.name}-duel1-flare.png`}); }
    await waitTurn(page);
    let last = await shoot(page, cdp, 10, 390, vp.touch);
    duel.shots++;
    duel.scriptedWin = Boolean(last && last.result === "A");
    for (let k = 0; k < 30; k++) {
      const [x, y] = followups[k % followups.length];
      if (!last || last.result || (await ds(page)).phase === "finished") break;
      await waitTurn(page);
      last = await shoot(page, cdp, x, y, vp.touch);
      if (last) duel.shots++;
    }
    await page.waitForFunction(() => document.getElementById("fogshot-field").dataset.phase === "finished", null, {timeout: 40000}).catch(() => {});
    const end = await ds(page);
    duel.result = end.result;
    run.duels.push(duel);
    if (n <= 2) { await page.waitForTimeout(900); await page.screenshot({path: `${out}${vp.name}-duel${n}-end.png`}); }
    if (end.phase !== "finished") { duel.note = "unfinished after follow-ups"; break; }
    const epoch = Number(end.epoch);
    await page.getByRole("button", {name: "Rematch", exact: true}).click();
    await page.waitForFunction(e => Number(document.getElementById("fogshot-field").dataset.epoch) > e, epoch, {timeout: 20000});
  }
  run.overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
  report.runs.push(run);
  await ctx.close();
}
await browser.close();
const all = report.runs.flatMap(r => r.duels || []);
report.summary = {
  duels: all.length,
  distinctRidges: new Set(all.map(d => d.ridge)).size,
  scriptedWins: all.filter(d => d.scriptedWin).length,
  humanWins: all.filter(d => d.result === "A").length,
  botWins: all.filter(d => d.result === "B").length,
  consoleErrors: report.runs.reduce((s, r) => s + r.console.filter(c => c.startsWith("error")).length + r.pageErrors.length, 0),
  consoleWarnings: report.runs.reduce((s, r) => s + r.console.filter(c => c.startsWith("warning")).length, 0),
};
fs.writeFileSync(`${out}proc-report.json`, JSON.stringify(report, null, 2));
console.log(JSON.stringify(report.summary));
