"""Compose qa/proc-layouts.png from the per-ridge captures written by qa/proc-playtest.mjs."""
import json
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

src = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/fogshot-proc")
dest = Path(__file__).resolve().parent / "proc-layouts.png"
report = json.loads((src / "proc-report.json").read_text())
tiles = [(r, src / f"ridge-{r['ridge']}.png") for r in report["ridges"]]
tiles = [(r, p) for r, p in tiles if p.exists()][:6]
w, h, label, pad = 640, 320, 30, 12
cols = 2 if len(tiles) <= 4 else 3
rows = (len(tiles) + cols - 1) // cols
sheet = Image.new("RGB", (pad + cols * (w + pad), 54 + rows * (h + label + pad)), "#0b2029")
draw = ImageDraw.Draw(sheet)
def font(size):
    for name in ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"]:
        if Path(name).exists():
            return ImageFont.truetype(name, size)
    return ImageFont.load_default()
draw.text((pad, 14), "FOGSHOT / generated ridges (seat A view at turn 0; enemy outpost hidden in fog)", fill="#dfeadf", font=font(20))
for i, (r, path) in enumerate(tiles):
    x = pad + (i % cols) * (w + pad)
    y = 54 + (i // cols) * (h + label + pad)
    sheet.paste(Image.open(path).convert("RGB").resize((w, h)), (x, y + label))
    lx, ly = r["launcher"]
    draw.text((x + 2, y + 4), f"{r['label']}   launcher ({lx:.2f}, {ly:.2f}) m", fill="#f1d18b", font=font(16))
sheet.save(dest)
print(dest)
