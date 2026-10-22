// Long-range artillery on a generated ridge: relative drag aim, locked aim + FIRE, the camera
// following the shell and returning home, the minimap strip and drag-pan. Desktop and phone.
import assert from "node:assert/strict";
import fs from "node:fs";
import {createRequire} from "node:module";
const require = createRequire(import.meta.url);
const {chromium} = require(process.env.FOGSHOT_PLAYWRIGHT || "playwright");
const url = process.env.FOGSHOT_URL || "http://127.0.0.1:8000/";
const browser = await chromium.launch({headless:true,channel:process.env.FOGSHOT_BROWSER_CHANNEL || undefined});
const errors = [];
async function capture(page, name) {
    if(!process.env.FOGSHOT_EVIDENCE) return;
    fs.mkdirSync(process.env.FOGSHOT_EVIDENCE,{recursive:true});
    await page.screenshot({path:process.env.FOGSHOT_EVIDENCE+"/"+name+".png"});
}
const data = page => page.evaluate(()=>({...document.getElementById("fogshot-field").dataset}));
async function run(vp) {
    const context = await browser.newContext(vp.touch
        ? {viewport:{width:390,height:844},hasTouch:true,isMobile:true,deviceScaleFactor:2}
        : {viewport:{width:1280,height:800}});
    const page = await context.newPage();
    page.on("pageerror",e=>errors.push(vp.name+": "+String(e)));
    const cdp = await context.newCDPSession(page);
    const practice = new URL(url); practice.searchParams.set("practice","1");
    await page.goto(practice.toString(),{waitUntil:"domcontentloaded"});
    await page.waitForFunction(()=>{const d=document.getElementById("fogshot-field")?.dataset;return d?.seat==="A" && d.yourTurn==="true" && d.fieldMode==="long";},null,{timeout:90000});
    const start = await data(page);
    assert.equal(start.fieldW,"160");
    assert.equal(start.camera,"home");
    assert.equal(Number(start.cameraX),0,"seat A home view should start at its own edge");
    assert.ok(await page.locator("#fogshot-fire").isDisabled(),"FIRE must wait for an aim");
    const b = await page.locator("#fogshot-field canvas").boundingBox();
    // Drag anywhere (relative): back 150 and down 110 canvas px.
    const sx=b.x+b.width*.6, sy=b.y+b.height*.5, ex=sx-150*b.width/800, ey=sy+110*b.height/400;
    if(vp.touch) {
        await cdp.send("Input.dispatchTouchEvent",{type:"touchStart",touchPoints:[{x:sx,y:sy}]});
        for(let i=1;i<=8;i++) await cdp.send("Input.dispatchTouchEvent",{type:"touchMove",touchPoints:[{x:sx+(ex-sx)*i/8,y:sy+(ey-sy)*i/8}]});
        await cdp.send("Input.dispatchTouchEvent",{type:"touchEnd",touchPoints:[]});
    } else {
        await page.mouse.move(sx,sy);await page.mouse.down();await page.mouse.move(ex,ey,{steps:8});await page.mouse.up();
    }
    await page.waitForFunction(()=>document.getElementById("fogshot-field").dataset.aimLocked==="true",null,{timeout:5000});
    const locked = await data(page);
    assert.ok(Math.abs(Number(locked.aimDegrees)-Math.atan2(110,150)*180/Math.PI)<0.6,"drag angle "+locked.aimDegrees);
    assert.ok(Math.abs(Number(locked.aimPercent)-Math.hypot(150,110)/240*100)<1.2,"drag power "+locked.aimPercent);
    assert.equal((await data(page)).yourTurn,"true","releasing the drag must not fire");
    // Fine-tune: half a degree up, half a percent more power.
    await page.locator("[data-aim='angle-up']").click();
    await page.locator("[data-aim='power-up']").click();
    const tuned = await data(page);
    assert.ok(Math.abs(Number(tuned.aimDegrees)-Number(locked.aimDegrees)-0.5)<0.05);
    assert.ok(Math.abs(Number(tuned.aimPercent)-Number(locked.aimPercent)-0.5)<0.05);
    await capture(page,`long-${vp.name}-aim`);
    const fired = page.waitForResponse(r=>r.request().method()==="POST" && r.url().includes("/function/loose_shot"));
    await page.locator("#fogshot-fire").click();
    const receipt = JSON.parse((await (await fired).json()).data.result);
    assert.ok(receipt.ok,"long-range flare rejected: "+receipt.code);
    assert.ok(receipt.path.length>8,"the shooter sees its whole arc");
    const far = Math.max(...receipt.path.map(p=>p[0]));
    assert.ok(far>60,"a long flare crosses the field, reached "+far);
    await page.waitForFunction(()=>document.getElementById("fogshot-field").dataset.camera==="follow",null,{timeout:5000});
    await page.waitForFunction(()=>Number(document.getElementById("fogshot-field").dataset.cameraX)>800,null,{timeout:8000});
    await capture(page,`long-${vp.name}-follow`);
    await page.waitForFunction(()=>{const d=document.getElementById("fogshot-field").dataset;return d.camera==="home" && Number(d.cameraX)<40;},null,{timeout:20000});
    // Minimap: touch the far end of the strip to look at the enemy side.
    await page.waitForFunction(()=>document.getElementById("fogshot-field").dataset.botThinking==="false",null,{timeout:30000});
    await page.waitForTimeout(1600);
    const strip = {x:b.x+b.width*.62, y:b.y+b.height*(22/400)};
    if(vp.touch) await page.touchscreen.tap(strip.x,strip.y); else await page.mouse.click(strip.x,strip.y);
    await page.waitForFunction(()=>{const d=document.getElementById("fogshot-field").dataset;return d.camera==="look" && Number(d.cameraX)>1200;},null,{timeout:5000});
    await capture(page,`long-${vp.name}-overview`);
    await page.locator("[data-aim='home']").click();
    await page.waitForFunction(()=>{const d=document.getElementById("fogshot-field").dataset;return d.camera==="home" && Number(d.cameraX)<40;},null,{timeout:8000});
    // The locked aim survives into the next turn so a correction starts from the last shot.
    assert.equal((await data(page)).aimLocked,"true");
    assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),"overflow at "+vp.name);
    await context.close();
}
try {
    await run({name:"desktop",touch:false});
    await run({name:"mobile",touch:true});
    assert.deepEqual(errors,[]);
    console.log("long range ok");
} finally { await browser.close(); }
