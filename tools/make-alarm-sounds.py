"""Makes Axiom's own alarm chime (App/Sounds/axiom-chime.wav): python3 tools/make-alarm-sounds.py

The chime: three bell notes, high-low-higher (G5, E5, C6), like a cabin chime that ends looking up.
It starts soft and grows: the first rounds are quiet and slow, then it gets louder, and from about
14 seconds the rounds come quicker with a second bell an octave up. 28 s long (iOS plays up to 30 s).
The dashboard plays the same notes with Web Audio for the preview, so keep the two in step."""
import math, wave, os, array

RATE = 22050
LEN = 28.0
NOTES = [783.99, 659.25, 1046.50]          # G5, E5, C6
GAPS = [0.0, 0.32, 0.64]                   # seconds into each round
PARTIALS = [(1.0, 1.0, 1.0), (2.0, .35, 1.6), (2.76, .22, 2.6), (5.40, .08, 4.5)]   # (ratio, level, faster decay) — a struck bell

def bell(f, x, decay):
    v = 0.0
    for r, a, d in PARTIALS:
        v += a * math.exp(-x * decay * d) * math.sin(2 * math.pi * f * r * x)
    return v * min(1.0, x / .002)

def rounds():
    t, out = 0.0, []
    while t < LEN:
        late = t >= 14.0
        out.append((t, late))
        t += 1.6 if late else 2.4
    return out

def chime():
    n = int(RATE * LEN); s = [0.0] * n
    for start, late in rounds():
        vol = .45 + .55 * min(1.0, start / 12.0)               # grows over the first 12 seconds
        for k, (f, g) in enumerate(zip(NOTES, GAPS)):
            t0 = start + g; i0 = int(t0 * RATE)
            for i in range(i0, min(n, i0 + int(RATE * 1.8))):
                x = (i - i0) / RATE
                v = bell(f, x, 2.2)
                if late: v += .35 * bell(f * 2, x, 3.0)           # the octave bell joins in
                s[i] += vol * v * (1.0 if k < 2 else 1.15)
    peak = max(abs(x) for x in s)
    return [x / peak * .9 for x in s]

out = os.path.join(os.path.dirname(__file__), '..', 'App', 'Sounds')
os.makedirs(out, exist_ok=True)
for old in ('axiom-beep.wav', 'axiom-buzz.wav'):
    p = os.path.join(out, old)
    if os.path.exists(p): os.remove(p)
data = array.array('h', (int(x * 32767) for x in chime()))
with wave.open(os.path.join(out, 'axiom-chime.wav'), 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(data.tobytes())
print('axiom-chime.wav', len(data) / RATE, 's')
