"""Compose qa/destruction.png from the captures written by qa/destruction-playtest.mjs and copy them to qa/destruction/."""
import json
import shutil
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

src = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/fogshot-destruction")
here = Path(__file__).resolve().parent
keep = here / "destruction"
keep.mkdir(exist_ok=True)
report = json.loads((src / "destruction-report.json").read_text())
CAPTIONS = {
    "1-before-blast": "ground before the blast", "2-blast": "shell burst + dirt clods", "3-after-blast": "crater carved, rim scorched",
    "4-incoming-blast": "bot's shell lands on our half", "5-home-after-exchange": "home after the exchange", "6-outpost-hit": "proof shell bursts on enemy outpost", "6b-outpost-debris": "after the hit, camera back home",
    "7-overview": "overview / minimap",
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
draw.text((pad, 14), "FOGSHOT / destruction: craters carved into the ridge, fractured blocks, debris (before / after blast)", fill="#dfeadf", font=font(22))
y = 60
for run, tiles, tw, per, h in sections:
    f = run["field"]
    name = "Desktop 1280x800" if run["vp"] == "desktop" else "Mobile 390x844 (touch)"
    fps = run.get("fpsSummary") or {}
    draw.text((pad, y + 6), f"{name}   ridge #{f['ridge']}, field {f['w']} m   client fps min {fps.get('min', '?')} / median {fps.get('median', '?')}", fill="#f1d18b", font=font(18))
    y += 34
    for i, (s, img) in enumerate(tiles):
        x = pad + (i % per) * (tw + pad)
        yy = y + (i // per) * (th + label + pad)
        draw.text((x + 2, yy + 4), f"{s['name']}: {CAPTIONS.get(s['name'], '')} [{s.get('craters', 0)} craters]"[:max(14, tw // 8)], fill="#dfeadf", font=font(13))
        sheet.paste(img, (x, yy + label))
    y += h
dest = here / "destruction.png"
sheet.save(dest)
print(dest)
