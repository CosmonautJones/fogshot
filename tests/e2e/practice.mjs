// Real solo practice lifecycle; no response stubs or privileged bot endpoints.
import assert from "node:assert/strict";
import fs from "node:fs";
import {createRequire} from "node:module";
const require = createRequire(import.meta.url);
const {chromium} = require(process.env.FOGSHOT_PLAYWRIGHT || "playwright");
const url = process.env.FOGSHOT_URL || "http://127.0.0.1:8000/";
const api = process.env.FOGSHOT_API || "http://127.0.0.1:8001";
const browser = await chromium.launch({headless:true,channel:process.env.FOGSHOT_BROWSER_CHANNEL || undefined});
const context = await browser.newContext({viewport:{width:1280,height:900}});
const page = await context.newPage();
const bodies = [];
const auth = new Map();
function observe(p) {
    p.on("request",r=>{if(r.url().includes("/function/") && r.headers().authorization) auth.set(p,r.headers().authorization);});
    p.on("response",async r=>{if(r.url().includes("/function/")){try{bodies.push(await r.text());}catch{}}});
}
observe(page);
async function state(p=page) {
    return p.evaluate(()=>{const d=document.getElementById("fogshot-field").dataset;return{
        mode:d.mode,turn:Number(d.turnNumber),epoch:Number(d.epoch),revision:Number(d.revision),
        phase:d.phase,result:d.result,thinking:d.botThinking,yourTurn:d.yourTurn,
        due:Number(d.botDueAt),room:d.room};});
}
async function ready(mode, p=page) {
    await p.waitForFunction(m=>{const d=document.getElementById("fogshot-field")?.dataset;return d?.seat==="A" && d.mode===m;},mode,{timeout:30000});
}
async function pull(x,y) {
    await page.waitForFunction(()=>document.getElementById("fogshot-field")?.dataset.yourTurn==="true",null,{timeout:20000});
    await page.locator("#fogshot-field").focus();
    const b=await page.locator("#fogshot-field canvas").boundingBox();
    const [response]=await Promise.all([
        page.waitForResponse(r=>r.request().method()==="POST" && r.url().includes("/function/loose_shot")),
        (async()=>{await page.mouse.move(b.x+120*b.width/800,b.y+300*b.height/400);await page.mouse.down();
            await page.mouse.move(b.x+x*b.width/800,b.y+y*b.height/400,{steps:6});await page.mouse.up();})()
    ]);
    const envelope=await response.json();
    const receipt=JSON.parse(envelope.data.result);
    assert.ok(response.ok() && receipt.ok, "real practice pull was rejected");
    return receipt;
}
async function call(p,name,args) {
    const response=await p.request.post(api+"/function/"+name,{headers:{authorization:auth.get(p)},data:args});
    const envelope=await response.json();
    return typeof envelope.data?.result==="string" ? JSON.parse(envelope.data.result) : envelope.data?.result;
}
async function capture(name) {
    if(!process.env.FOGSHOT_EVIDENCE) return;
    fs.mkdirSync(process.env.FOGSHOT_EVIDENCE,{recursive:true});
    await page.screenshot({path:process.env.FOGSHOT_EVIDENCE+"/"+name+".png",fullPage:true,
        maskColor:"#0b2029",mask:[page.locator("#fogshot-room"),page.locator("#fogshot-caption")]});
}
try {
    const missing=new URL(url);missing.search="";missing.searchParams.set("room","000000");
    await page.goto(missing.href,{waitUntil:"domcontentloaded"});
    await page.waitForFunction(()=>document.getElementById("fogshot-caption")?.textContent.includes("unavailable"),null,{timeout:30000});
    assert.equal(await page.getByRole("button",{name:"Practice",exact:true}).count(),1,"Practice button is missing");
    await page.getByRole("button",{name:"Practice",exact:true}).click();
    await ready("practice");
    assert.match(await page.locator(".room-card").innerText(),/SOLO PRACTICE/i);
    assert.doesNotMatch(await page.locator("footer").innerText(),/Send this page URL/);
    const start=await state();
    await capture("practice-own-turn");
    // Hold only automatic watch transport; APIRequestContext calls still reach the real server.
    const holdPoll=route=>route.abort("failed");
    await page.route("**/function/watch_match",holdPoll);
    const flare=await pull(20,300);
    assert.ok(flare.bot_due_at>=flare.reveal_until+400,"bot deadline truncates the reveal");
    await page.waitForFunction(()=>document.getElementById("fogshot-field")?.dataset.botThinking==="true");
    const thinking=await state();
    assert.equal(thinking.turn,1);
    assert.ok(thinking.due>Date.now()+1200,"bot pause did not protect the reveal");
    await page.waitForTimeout(800);
    assert.equal((await state()).turn,1,"bot fired during human reveal");
    await page.reload({waitUntil:"domcontentloaded"});
    await ready("practice");
    assert.equal((await state()).room,start.room,"reload created another practice room");
    await page.waitForTimeout(Math.max(0,thinking.due-Date.now()+30));
    const simultaneous=await Promise.all(Array.from({length:3},()=>call(page,"watch_match",{invite:start.room,now_ms:9999999999999})));
    assert.ok(simultaneous.every(d=>d.turn===2 && d.revision===2 && d.your_turn),"concurrent due polls did not produce one bot move");
    await page.unroute("**/function/watch_match",holdPoll);
    await page.waitForFunction(()=>{const d=document.getElementById("fogshot-field").dataset;return d.turnNumber==="2" && d.yourTurn==="true";},null,{timeout:20000});
    const intruderContext=await browser.newContext();
    const intruder=await intruderContext.newPage();observe(intruder);
    await intruder.goto(url,{waitUntil:"domcontentloaded"});
    await intruder.waitForFunction(()=>document.getElementById("fogshot-field")?.dataset.seat==="A",null,{timeout:30000});
    for (const name of ["join_seat","watch_match"]) {
        const denied=await call(intruder,name,{invite:start.room,now_ms:0});
        assert.equal(denied.ok,false,"another account entered practice");
        assert.equal(denied.seat,"");
    }
    await intruderContext.close();
    await pull(10,390);
    await page.waitForFunction(()=>document.getElementById("fogshot-field").dataset.result==="A",null,{timeout:20000});
    assert.equal(await page.locator("#fogshot-turn").innerText(),"Victory");
    await capture("practice-victory");
    await page.getByRole("button",{name:"Rematch",exact:true}).click();
    await page.waitForFunction(e=>Number(document.getElementById("fogshot-field").dataset.epoch)>e,start.epoch);
    let releaseDelayed, capturedDelayed;
    const delayGate=new Promise(resolve=>{releaseDelayed=resolve;});
    const capturedGate=new Promise(resolve=>{capturedDelayed=resolve;});
    let held=false;
    const delayedRoute=async route=>{
        if(route.request().method()!=="POST") return route.continue();
        const response=await route.fetch();
        const envelope=await response.json();
        const data=JSON.parse(envelope.data.result);
        if(!held && data.turn===1) {
            held=true;capturedDelayed();
            await delayGate;
        }
        await route.fulfill({response});
    };
    await page.route("**/function/watch_match",delayedRoute);
    await pull(20,300);
    await Promise.race([capturedGate,new Promise((_,reject)=>setTimeout(()=>reject(new Error("no real turn-1 poll captured")),10000))]);
    await page.waitForFunction(()=>document.getElementById("fogshot-field").dataset.turnNumber==="2",null,{timeout:20000});
    releaseDelayed();
    await page.waitForTimeout(250);
    await page.unroute("**/function/watch_match",delayedRoute);
    await pull(20,300);
    await page.waitForFunction(()=>document.getElementById("fogshot-field").dataset.result==="B",null,{timeout:20000});
    assert.equal(await page.locator("#fogshot-turn").innerText(),"Outpost lost");
    await capture("practice-loss");
    await page.getByRole("button",{name:"Rematch",exact:true}).click();
    await page.waitForFunction(()=>document.getElementById("fogshot-field").dataset.phase==="recon");
    await page.setViewportSize({width:390,height:844});
    await pull(20,300);
    await capture("practice-mobile-thinking");
    await page.getByRole("button",{name:"Multiplayer",exact:true}).click();
    await ready("multiplayer");
    assert.equal(new URL(page.url()).searchParams.has("practice"),false);
    const multiplayer=await state();
    await page.waitForTimeout(3800);
    assert.equal((await state()).turn,0,"old practice poll changed multiplayer");
    assert.notEqual(multiplayer.room,start.room);
    await page.reload({waitUntil:"domcontentloaded"});
    await ready("multiplayer");
    assert.equal((await state()).room,multiplayer.room);
    assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),"mobile overflow");
    await capture("returned-multiplayer");
    for(const text of bodies) {
        for(const forbidden of ["12345.67","-9876.54","87654.32","practice-bot-",'\"memory\"','\"plan\"','\"owner\"']) {
            assert.equal(text.includes(forbidden),false,"private field leaked: "+forbidden);
        }
    }
    console.log("practice lifecycle ok");
} finally { await browser.close(); }
