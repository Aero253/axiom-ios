# python3 tools/make-dot-font.py Shared/DotGlyphs.swift Widgets/AxiomDots.ttf
"""Build AxiomDots.ttf: Axiom's 5×7 dot letters as a real font, so the iPhone can tick a countdown in dots."""
import re, sys, math
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

src = open(sys.argv[1]).read()
glyphs = {}
for ch, rows in re.findall(r'"(.)": \[((?:"[01]+",? ?)+)\]', src):
    glyphs[ch] = re.findall(r'"([01]+)"', rows)
assert '0' in glyphs and ':' in glyphs, glyphs.keys()

P = 140          # dot pitch
R = P * 0.40     # dot radius
UPM = 1000
names = {' ': 'space', ':': 'colon', '.': 'period', '-': 'hyphen', '+': 'plus', '/': 'slash', '%': 'percent', '?': 'question'}
def gname(ch):
    if ch in names: return names[ch]
    if ch.isdigit(): return ['zero','one','two','three','four','five','six','seven','eight','nine'][int(ch)]
    return ch if ch.isalpha() else 'uni%04X' % ord(ch)

def circle(pen, cx, cy, r):
    n = 8
    k = r / math.cos(math.pi / n)
    pts = []
    for i in range(n):               # clockwise
        a = -2 * math.pi * i / n
        pts.append((round(cx + r * math.cos(a)), round(cy + r * math.sin(a))))
    pen.moveTo(pts[0])
    for i in range(n):
        a = -2 * math.pi * (i + .5) / n
        off = (round(cx + k * math.cos(a)), round(cy + k * math.sin(a)))
        pen.qCurveTo(off, pts[(i + 1) % n])
    pen.closePath()

order = ['.notdef']
cmap, metrics, gl = {}, {}, {}
pen = TTGlyphPen(None)
gl['.notdef'] = pen.glyph(); metrics['.notdef'] = (5 * P, 0)
for ch, rows in glyphs.items():
    n = gname(ch)
    pen = TTGlyphPen(None)
    w = len(rows[0])
    for r, row in enumerate(rows):
        for c, bit in enumerate(row):
            if bit == '1':
                circle(pen, int(P * (c + .5) + P * .5), int(P * (6 - r + .5) - P * .5 + 20), R)
    gl[n] = pen.glyph()
    metrics[n] = ((w + 1) * P, 0)
    order.append(n); cmap[ord(ch)] = n
    if ch.isalpha() and ch.isupper(): cmap[ord(ch.lower())] = n

fb = FontBuilder(UPM, isTTF=True)
fb.setupGlyphOrder(order)
fb.setupCharacterMap(cmap)
fb.setupGlyf(gl)
fb.setupHorizontalMetrics(metrics)
fb.setupHorizontalHeader(ascent=1000, descent=-120)
fb.setupNameTable({'familyName': 'Axiom Dots', 'styleName': 'Regular', 'psName': 'AxiomDots-Regular', 'fullName': 'Axiom Dots'})
fb.setupOS2(sTypoAscender=1000, sTypoDescender=-120, usWinAscent=1000, usWinDescent=120, sxHeight=700, sCapHeight=980)
fb.setupPost()
fb.save(sys.argv[2])
print(len(order), 'glyphs')
