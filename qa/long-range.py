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
def grid_h(n, h):
    return ((n + cols - 1) // cols) * (h + label + pad)
mw = max((i.width for _, i in mob), default=200)
width = pad + cols * (400 + pad)
height = 60 + 34 + grid_h(len(desk), th) + 34 + ((len(mob) + 8) // 9) * (th + label + pad)
sheet = Image.new("RGB", (width, height), "#0b2029")
draw = ImageDraw.Draw(sheet)
f = rows[0][0]["field"] if rows else {}
draw.text((pad, 14), f"FOGSHOT / long-range artillery   field {f.get('w')} m (was 40 m), ridge #{f.get('ridge')}", fill="#dfeadf", font=font(22))
y = 60
for title, tiles, tw in [("Desktop 1280x800", desk, 400), ("Mobile 390x844 (touch)", mob, mw)]:
    draw.text((pad, y + 6), title, fill="#f1d18b", font=font(18))
    y += 34
    per = cols if tw == 400 else max(1, (width - pad) // (tw + pad))
    for i, (s, img) in enumerate(tiles):
        x = pad + (i % per) * (tw + pad)
        yy = y + (i // per) * (th + label + pad)
        draw.text((x + 2, yy + 4), f"{s['name']}: {CAPTIONS.get(s['name'], '')}"[:44], fill="#dfeadf", font=font(13))
        sheet.paste(img, (x, yy + label))
    y += ((len(tiles) + per - 1) // per) * (th + label + pad) if tiles else 0
sheet = sheet.crop((0, 0, width, y + pad))
dest = here / "long-range.png"
sheet.save(dest)
print(dest)
