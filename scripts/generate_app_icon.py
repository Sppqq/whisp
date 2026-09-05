#!/usr/bin/env python3
"""Generate the Whisp macOS AppIcon asset with Pillow."""

from pathlib import Path
import json

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Whisp" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
SPECS = [(16, "1x"), (32, "2x"), (32, "1x"), (64, "2x"), (128, "1x"),
         (256, "2x"), (256, "1x"), (512, "2x"), (512, "1x"), (1024, "2x")]


def make_icon() -> Image.Image:
    size = 1024
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    for y in range(64, 960):
        ratio = (y - 64) / 896
        color = tuple(round(a + (b - a) * ratio) for a, b in zip((31, 32, 38), (18, 19, 23))) + (255,)
        draw.line((64, y, 960, y), fill=color, width=1)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((64, 64, 960, 960), radius=220, fill=255)
    image.putalpha(mask)

    glow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse((206, 206, 818, 818), fill=(240, 91, 80, 105))
    glow = glow.filter(ImageFilter.GaussianBlur(95))
    image.alpha_composite(glow)

    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((236, 236, 788, 788), radius=150, fill=(239, 99, 87, 255))
    draw.rounded_rectangle((250, 250, 774, 774), radius=137, outline=(255, 255, 255, 35), width=3)

    bars = [(330, 438, 330, 586), (404, 368, 404, 656), (478, 306, 478, 718),
            (552, 374, 552, 650), (626, 442, 626, 582), (700, 478, 700, 546)]
    for x1, y1, _, y2 in bars:
        draw.line((x1, y1, x1, y2), fill=(255, 249, 246, 255), width=34)
        radius = 17
        draw.ellipse((x1 - radius, y1 - radius, x1 + radius, y1 + radius), fill=(255, 249, 246, 255))
        draw.ellipse((x1 - radius, y2 - radius, x1 + radius, y2 + radius), fill=(255, 249, 246, 255))
    return image


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    icon = make_icon()
    images = []
    logical_sizes = [16, 16, 32, 32, 128, 128, 256, 256, 512, 512]
    scales = ["1x", "2x", "1x", "2x", "1x", "2x", "1x", "2x", "1x", "2x"]
    pixels = [16, 32, 32, 64, 128, 256, 256, 512, 512, 1024]
    for logical, scale, pixel_size in zip(logical_sizes, scales, pixels):
        filename = f"whisp-{pixel_size}.png"
        icon.resize((pixel_size, pixel_size), Image.Resampling.LANCZOS).save(OUTPUT / filename)
        images.append({"filename": filename, "idiom": "mac", "scale": scale, "size": f"{logical}x{logical}"})
    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    (OUTPUT / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")
    catalog = OUTPUT.parent / "Contents.json"
    catalog.write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
