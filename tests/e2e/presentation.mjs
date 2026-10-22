// Against the real Jac application. No response stubs or browser-owned match.
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.FOGSHOT_PLAYWRIGHT || "playwright");
const evidence = process.env.FOGSHOT_EVIDENCE;
if (evidence) fs.mkdirSync(evidence, { recursive: true });
const browser = await chromium.launch({headless:true,channel:process.env.FOGSHOT_BROWSER_CHANNEL || undefined});
const context = await browser.newContext({viewport:{width:1280,height:1000},hasTouch:true});
const page = await context.newPage();
const errors = [];
// Ridge 0 is the classic hand-tuned fixture used by the scripted pulls below.
const classicUrl = (() => { const u = new URL(process.env.FOGSHOT_URL || "http://127.0.0.1:8000/"); u.searchParams.set("ridge","0"); return u.toString(); })();
let shots = 0;
const receipts = [];
page.on("response",async response=>{if(response.url().includes("/function/loose_shot")){try{const body=await response.json();const data=JSON.parse(body.data.result);receipts.push({ok:data.ok,code:data.code,phase:data.phase,turn:data.turn});}catch{}}});
page.on("pageerror", error => errors.push(String(error)));
page.on("request", request => { if (request.method() === "POST" && request.url().includes("/function/loose_shot")) shots++; });
const profileFrames = () => page.evaluate(()=>new Promise(resolve=>{const times=[];let previous=performance.now();const tick=now=>{times.push(now-previous);previous=now;if(times.length<120)requestAnimationFrame(tick);else{times.sort((a,b)=>a-b);resolve({medianMs:times[60],p95Ms:times[114],frames:times.length});}};requestAnimationFrame(tick);}));
const screenshot = async name => { if (evidence) await page.screenshot({path:path.join(evidence,name),fullPage:true,style:"#fogshot-room{font-size:0}#fogshot-room:after{content:'PRIVATE';font-size:13px}#fogshot-caption{visibility:hidden}"}); };
let unblockJoin;
const joinGate=new Promise(resolve=>{unblockJoin=resolve;});
await page.route("**/function/join_seat",async route=>{await joinGate;await route.continue();});
try {
    await page.goto(classicUrl,{waitUntil:"domcontentloaded"});
    await page.waitForSelector("#fogshot-field");
    const faults=[];
    if(await page.locator("#fogshot-turn").textContent()!=="Connecting...") faults.push("startup turn placeholder is damaged");
    if(await page.locator("#fogshot-supply").textContent()!=="Connecting...") faults.push("startup supply placeholder is damaged");
    if(await page.locator("#fogshot-cores").textContent()!=="-") faults.push("startup objective placeholder is damaged");
    if(!await page.locator("#fogshot-pull").isVisible()) faults.push("launch help is hidden");
    if(await page.locator("#fogshot-field").getAttribute("aria-describedby")!=="fogshot-pull") faults.push("field has no accessible control description");
    await screenshot("first-play-startup.png");
    assert.deepEqual(faults,[],"first-play control help and loading copy");
    unblockJoin();
    await page.unrouteAll({behavior:"wait"});
    await page.waitForFunction(()=>document.getElementById("fogshot-field")?.dataset.yourTurn === "true",null,{timeout:30000});
    await page.waitForSelector("canvas");
    const loaded = await page.evaluate(()=>({
        startupHeldForChecks:true,
        overflow:document.documentElement.scrollWidth > innerWidth,
        gameReadyMs:performance.now(),
        navigationMs:performance.getEntriesByType("navigation")[0].domContentLoadedEventEnd,
        resources:performance.getEntriesByType("resource").filter(r=>/\.(js|css|svg)(\?|$)/.test(r.name)).map(r=>({name:new URL(r.name).pathname.split("/").pop(),bytes:r.transferSize,durationMs:r.duration})),
    }));
    assert.equal(loaded.overflow,false);
    await page.getByRole("button",{name:"Practice",exact:true}).focus();
    await page.keyboard.press("Tab");
    assert.equal(await page.evaluate(()=>document.activeElement?.id),"fogshot-field","Tab did not reach battlefield");
    await page.keyboard.press("ArrowDown");
    assert.match(await page.locator("#fogshot-pull").innerText(),/Pull .*Enter to launch/);
    assert.equal(await page.locator("#fogshot-pull").isVisible(),true);
    await page.keyboard.press("Escape");
    assert.match(await page.locator("#fogshot-pull").innerText(),/arrows aim/);
    assert.equal(shots,0,"onboarding keyboard cancellation fired");
    await screenshot("after-desktop.png");
    await page.setViewportSize({width:390,height:844});
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth > innerWidth),false);
    const field=page.locator("#fogshot-field");
    let box=await page.locator("#fogshot-field canvas").boundingBox();
    const point=(x,y)=>({x:box.x+x*box.width/800,y:box.y+y*box.height/400});
    let start=point(120,300), end=point(20,300);
    const cdp=await context.newCDPSession(page);
    const touch=(id,p)=>({id,x:p.x,y:p.y,radiusX:3,radiusY:3,force:1});
    await cdp.send("Input.dispatchTouchEvent",{type:"touchStart",touchPoints:[touch(1,start)]});
    await cdp.send("Input.dispatchTouchEvent",{type:"touchMove",touchPoints:[touch(1,end)]});
    await cdp.send("Input.dispatchTouchEvent",{type:"touchCancel",touchPoints:[]});
    await page.waitForTimeout(100);
    assert.equal(shots,0,"OS touch cancellation fired a shot");
    await cdp.send("Input.dispatchTouchEvent",{type:"touchStart",touchPoints:[touch(1,start)]});
    await cdp.send("Input.dispatchTouchEvent",{type:"touchStart",touchPoints:[touch(1,start),touch(2,point(160,300))]});
    await cdp.send("Input.dispatchTouchEvent",{type:"touchMove",touchPoints:[touch(1,end),touch(2,point(160,300))]});
    await cdp.send("Input.dispatchTouchEvent",{type:"touchEnd",touchPoints:[]});
    await page.waitForTimeout(100);
    assert.equal(shots,0,"a second pointer contaminated the shot");
    await field.focus(); await page.keyboard.press("Escape");
    await page.keyboard.press("ArrowDown");
    assert.equal(await page.locator("#fogshot-pull").isVisible(),true,"mobile aim feedback is hidden");
    await screenshot("after-mobile-aim.png");
    // Switch directly from keyboard to pointer, then release outside to cancel.
    await page.mouse.move(start.x,start.y); await page.mouse.down();
    await page.mouse.move(box.x-5,box.y+box.height/2); await page.mouse.up();
    assert.equal(shots,0,"outside release fired");
    await field.focus(); await page.keyboard.press("ArrowDown");
    box=await page.locator("#fogshot-field canvas").boundingBox();
    start=point(120,300); end=point(20,300);
    await page.mouse.move(start.x,start.y); await page.mouse.down();
    await page.mouse.move(end.x,end.y,{steps:6});
    assert.ok(Math.abs(Number(await field.getAttribute("data-pointer-x"))-20)<2,"scaled pointer X differs from the intended pull");
    assert.ok(Math.abs(Number(await field.getAttribute("data-pointer-y"))-300)<2,"scaled pointer Y differs from the intended pull");
    await page.mouse.up();
    await page.waitForFunction(()=>document.getElementById("fogshot-field")?.dataset.reveal === "open",null,{timeout:15000});
    assert.equal(shots,1,"keyboard-to-pointer switch did not submit exactly one shot");
    assert.doesNotMatch(await page.locator("#fogshot-pull").innerText(),/Pull \d|Enter to launch/,"old aim guidance survived turn loss");
    await screenshot("after-mobile-reveal.png");
    // Block subsequent watches: observation must still expire using wall time.
    await page.route("**/function/watch_match",route=>route.abort());
    const effectFrames = await profileFrames();
    await page.waitForFunction(()=>document.getElementById("fogshot-field")?.dataset.reveal === "closed",null,{timeout:5000});
    assert.equal(await field.getAttribute("data-shot-screen-x"),"");
    assert.match(await page.locator("#fogshot-observation").textContent(),/HIDDEN/);
    await page.unroute("**/function/watch_match");
    await page.goto(classicUrl,{waitUntil:"domcontentloaded"});
    await page.waitForFunction(()=>document.getElementById("fogshot-field")?.dataset.yourTurn === "true",null,{timeout:15000});
    await field.focus(); await page.keyboard.press("ArrowDown"); await page.keyboard.press("Enter");
    await page.waitForFunction(()=>Number(document.getElementById("fogshot-field")?.dataset.revision)>0,null,{timeout:15000});
    assert.equal(shots,2,"keyboard launch did not submit exactly one shot");
    await page.emulateMedia({reducedMotion:"reduce"});
    await page.reload();
    await page.waitForFunction(()=>Boolean(document.getElementById("fogshot-field")?.dataset.seat),null,{timeout:15000});
    await screenshot("after-mobile-reduced-motion.png");
    const frames=await profileFrames();
    assert.deepEqual(errors,[]);
    const result={checks:["desktop/mobile fit","touch cancel","second touch","outside cancel","keyboard/pointer switch","wall-clock reveal expiry without polls","keyboard launch","reduced-motion page"],loaded,effectFrames,frames,pageErrors:errors};
    if(evidence)fs.writeFileSync(path.join(evidence,"presentation-metrics.json"),JSON.stringify(result,null,2));
    console.log(JSON.stringify(result));
    console.log("presentation interactions ok");
} catch(error) {
    console.error(JSON.stringify({shots,receipts,state:await page.evaluate(()=>{const d=document.getElementById("fogshot-field")?.dataset || {};return {seat:d.seat,turn:d.yourTurn,reveal:d.reveal,cancelled:d.cancelled,pointerX:d.pointerX,pointerY:d.pointerY,releaseX:d.releaseX,releaseY:d.releaseY,pulls:d.pulls,phase:d.phase,revision:d.revision};})}));
    await screenshot("failure.png");
    throw error;
} finally { unblockJoin(); await browser.close(); }
