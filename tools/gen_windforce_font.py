#!/usr/bin/env python3
"""Generate BMFont assets for a DejaVu Sans-derived Wind Force font set.

Creates 3 Garmin-compatible BMFont text files and sprite sheets:
    - resources/fonts/windforce_s.fnt + windforce_s_0.png
    - resources/fonts/windforce_m.fnt + windforce_m_0.png
    - resources/fonts/windforce_l.fnt + windforce_l_0.png

The glyph set matches the Wind Force display needs.

Important Connect IQ compatibility note:
the target runtime reliably resolves ASCII glyphs from BMFont resources, but
non-ASCII glyphs (such as U+2022 and U+2190-U+2199) may render as tofu boxes.
To avoid that, this font maps the visual bullet/arrow glyphs onto ASCII
placeholder code points that are remapped at runtime before drawing.
"""

import os
import sys

sys.stdout.reconfigure(encoding="utf-8")

from PIL import Image, ImageDraw, ImageFont

GLYPHS = [
    ("0", "0"),
    ("1", "1"),
    ("2", "2"),
    ("3", "3"),
    ("4", "4"),
    ("5", "5"),
    ("6", "6"),
    ("7", "7"),
    ("8", "8"),
    ("9", "9"),
    ("/", "/"),
    ("-", "-"),
    ("*", "*"),
    ("|", chr(0x2022)),  # slot separator bullet
    ("a", chr(0x2190)),  # left arrow
    ("b", chr(0x2191)),  # up arrow
    ("c", chr(0x2192)),  # right arrow
    ("d", chr(0x2193)),  # down arrow
    ("e", chr(0x2196)),  # up-left arrow
    ("f", chr(0x2197)),  # up-right arrow
    ("g", chr(0x2198)),  # down-right arrow
    ("h", chr(0x2199)),  # down-left arrow
]

# DejaVu Sans is the closest local, inspectable match to Garmin's Vera Sans.
FONT_PATH = "C:/Windows/Fonts/DejaVuSans.ttf"

# Instinct 2 / 2X English/Latin built-in font sizes:
#   FONT_XTINY/TINY/SMALL = 16 px
#   FONT_MEDIUM           = 21 px
#   FONT_LARGE            = 27 px
SIZES = {
    "s": 16,
    "m": 21,
    "l": 27,
}

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "resources", "fonts")


def generate_font(name: str, px_size: int, out_dir: str) -> tuple[int, int]:
    """Generate a BMFont .fnt + .png pair. Returns (fnt_size, png_size)."""
    font = ImageFont.truetype(FONT_PATH, px_size)

    glyphs = []
    for codepoint_char, render_char in GLYPHS:
        bbox = font.getbbox(render_char)
        width = bbox[2] - bbox[0]
        height = bbox[3] - bbox[1]
        glyphs.append(
            {
                "render_char": render_char,
                "codepoint": ord(codepoint_char),
                "width": width,
                "height": height,
                "x_offset": bbox[0],
                "y_offset": bbox[1],
            }
        )

    ascent, descent = font.getmetrics()
    line_height = ascent + descent

    padding = 1
    x_cursor = padding
    max_h = 0
    for glyph in glyphs:
        glyph["sheet_x"] = x_cursor
        glyph["sheet_y"] = padding
        x_cursor += glyph["width"] + padding
        max_h = max(max_h, glyph["height"])

    sheet_w = x_cursor
    sheet_h = max_h + padding * 2

    img = Image.new("L", (sheet_w, sheet_h), 0)
    draw = ImageDraw.Draw(img)
    for glyph in glyphs:
        draw.text(
            (glyph["sheet_x"] - glyph["x_offset"], glyph["sheet_y"] - glyph["y_offset"]),
            glyph["render_char"],
            font=font,
            fill=255,
        )

    png_path = os.path.join(out_dir, f"windforce_{name}_0.png")
    img.save(png_path, optimize=True)
    png_size = os.path.getsize(png_path)

    fnt_lines = [
        (
            f'info face="WindForce" size=-{px_size} bold=0 italic=0 charset="" '
            f"unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1 outline=0"
        ),
        (
            f"common lineHeight={line_height} base={ascent} "
            f"scaleW={sheet_w} scaleH={sheet_h} pages=1 packed=0 "
            f"alphaChnl=1 redChnl=0 greenChnl=0 blueChnl=0"
        ),
        f'page id=0 file="windforce_{name}_0.png"',
        f"chars count={len(glyphs)}",
    ]

    for glyph in glyphs:
        xadvance = glyph["width"] + 1
        fnt_lines.append(
            f"char id={glyph['codepoint']:<5d} "
            f"x={glyph['sheet_x']:<5d} y={glyph['sheet_y']:<5d} "
            f"width={glyph['width']:<5d} height={glyph['height']:<5d} "
            f"xoffset={glyph['x_offset']:<5d} yoffset={glyph['y_offset']:<5d} "
            f"xadvance={xadvance:<5d} page=0  chnl=15"
        )

    fnt_path = os.path.join(out_dir, f"windforce_{name}.fnt")
    with open(fnt_path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(fnt_lines) + "\n")
    fnt_size = os.path.getsize(fnt_path)

    return fnt_size, png_size


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    total = 0
    for name, px_size in SIZES.items():
        fnt_size, png_size = generate_font(name, px_size, OUT_DIR)
        combined = fnt_size + png_size
        total += combined
        print(
            f"  windforce_{name}: {fnt_size:,} (fnt) + "
            f"{png_size:,} (png) = {combined:,} bytes"
        )

    print(f"\n  Total font files: {total:,} bytes ({total/1024:.1f} KB)")


if __name__ == "__main__":
    main()
