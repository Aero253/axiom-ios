"""Axiom's icon: the dashboard's 5-dot mark (a 3×3 grid, corners and centre lit), white on black.
python3 tools/make-icon.py  →  App/Assets.xcassets/AppIcon.appiconset/icon-1024.png (+ web icons if a path is given)"""
import sys
from PIL import Image, ImageDraw

def icon(size):
    s = 4  # draw big, then shrink for smooth dots
    W = size * s
    im = Image.new('RGB', (W, W), (0, 0, 0)); d = ImageDraw.Draw(im)
    pitch = W * 0.23; r = pitch * 0.36; c0 = W / 2 - pitch
    for row in range(3):
        for col in range(3):
            lit = (row * 3 + col) % 2 == 0          # same as the dashboard: every other dot, so corners and centre
            cx, cy = c0 + col * pitch, c0 + row * pitch
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255) if lit else (46, 46, 46))
    return im.resize((size, size), Image.LANCZOS)

icon(1024).save('App/Assets.xcassets/AppIcon.appiconset/icon-1024.png')
for p in sys.argv[1:]:
    for n in (192, 512): icon(n).save(f'{p}/icon-{n}.png')
print('ok')
