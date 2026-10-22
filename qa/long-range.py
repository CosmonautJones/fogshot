"""Compose qa/long-range.png from the captures written by qa/long-playtest.mjs and copy them to qa/long-range/."""
import json
import shutil
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

src = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/fogshot-long")
here = Path(__file__).resolve().parent
keep = here / "long-range"
keep.mkdir(exist_ok=True)
report = json.loads((src / "long-report.json").read_text())
CAPTIONS = {
    "1-home": "home view (own launcher)", "2-aim": "drag-locked aim + readout", "3-follow-early": "camera follows shell",
    "4-follow-far": "follow, far downrange", "5-burst-reveal": "burst + local reveal", "6-incoming": "bot's incoming shell",
    "7-overview-look": "minimap look at enemy side", "8-home-again": "back home", "9-shell-flight": "second (shell) flight",
}
def font(size):
    for name in ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"]:
        if Path(name).exists():
            return ImageFont.truetype(name, size)
    return ImageFont.load_default()
pad, label = 12, 26
rows = []
for run in report["runs"]:
    tiles = []
    for s in run["shots"]:
        p = Path(s["path"])
        if p.exists():
            shutil.copy(p, keep / p.name)
            tiles.append((s, Image.open(p).convert("RGB")))
    rows.append((run, tiles))
# Desktop tiles 400 wide; mobile tiles scaled to the same height as desktop's.
def fit(img, w):
    return img.resize((w, round(img.height * w / img.width)))
desk = [(s, fit(i, 400)) for s, i in rows[0][1]] if rows else []
th = max((i.height for _, i in desk), default=260)
mob = [(s, i.resize((round(i.width * th / i.height), th))) for s, i in (rows[1][1] if len(rows) > 1 else [])]
cols = 5
mw = max((i.width for _, i in mob), default=200)
width = pad + cols * (400 + pad)
sections = []
for run, tiles, tw in [(rows[0][0] if rows else None, desk, 400), (rows[1][0] if len(rows) > 1 else None, mob, mw)]:
    if run is None:
        continue
    per = max(1, (width - pad) // (tw + pad))
    sections.append((run, tiles, tw, per, ((len(tiles) + per - 1) // per) * (th + label + pad)))
height = 60 + sum(34 + h for *_, h in sections) + pad
sheet = Image.new("RGB", (width, height), "#0b2029")
draw = ImageDraw.Draw(sheet)
draw.text((pad, 14), "FOGSHOT / long-range artillery: camera follow, burst, incoming shell, minimap look (classic field was 40 m)", fill="#dfeadf", font=font(22))
y = 60
for run, tiles, tw, per, h in sections:
    f = run["field"]
    name = "Desktop 1280x800" if run["vp"] == "desktop" else "Mobile 390x844 (touch)"
    draw.text((pad, y + 6), f"{name}   ridge #{f['ridge']}, field {f['w']} m", fill="#f1d18b", font=font(18))
    y += 34
    for i, (s, img) in enumerate(tiles):
        x = pad + (i % per) * (tw + pad)
        yy = y + (i // per) * (th + label + pad)
        draw.text((x + 2, yy + 4), f"{s['name']}: {CAPTIONS.get(s['name'], '')}"[:max(14, tw // 8)], fill="#dfeadf", font=font(13))
        sheet.paste(img, (x, yy + label))
    y += h
dest = here / "long-range.png"
sheet.save(dest)
print(dest)
