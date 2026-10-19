"""Generate platform icon resources from the checked-in logo; requires Pillow.

Run from any directory: python frontend/tool/generate_app_icons.py
This generates images only; it does not build the application.
"""

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/branding/app_icon.png"
logo = Image.open(SOURCE).convert("RGB")
assert logo.width == logo.height, "The app logo must be square"
generated = {}


def png(relative, size, padding=0):
    target = ROOT / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGB", (size, size), "black")
    inner = round(size * (1 - 2 * padding))
    resized = logo.resize((inner, inner), Image.Resampling.LANCZOS)
    image.paste(resized, ((size - inner) // 2, (size - inner) // 2))
    image.save(target, optimize=True)
    generated[target] = size


for density, size in {
    "mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192
}.items():
    png(f"android/app/src/main/res/mipmap-{density}/ic_launcher.png", size)

# Android's foreground is 108 dp; keep the mark inside its 66 dp safe zone.
png("android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png", 432, .16)

for platform in ("ios", "macos"):
    catalog = ROOT / platform / "Runner/Assets.xcassets/AppIcon.appiconset"
    manifest = json.loads((catalog / "Contents.json").read_text(encoding="utf-8"))
    for entry in manifest["images"]:
        if "filename" in entry:
            size = round(float(entry["size"].split("x")[0]) * float(entry["scale"][:-1]))
            png((catalog / entry["filename"]).relative_to(ROOT), size)

for size in (192, 512):
    png(f"web/icons/Icon-{size}.png", size)
    png(f"web/icons/Icon-maskable-{size}.png", size, .1)
png("web/favicon.png", 32)

ico = ROOT / "windows/runner/resources/app_icon.ico"
sizes = [16, 24, 32, 48, 64, 128, 256]
logo.resize((256, 256), Image.Resampling.LANCZOS).save(
    ico, sizes=[(size, size) for size in sizes]
)

for path, size in generated.items():
    with Image.open(path) as image:
        assert image.size == (size, size), f"Unexpected icon size: {path}"
        assert image.mode == "RGB", f"Icon must have no alpha channel: {path}"
with Image.open(ico) as image:
    assert image.ico.sizes() == {(size, size) for size in sizes}

print(f"Generated and verified {len(generated)} PNG icons and {len(sizes)} Windows icon sizes.")
