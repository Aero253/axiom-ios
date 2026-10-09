"""Makes Axiom's alarm sound (App/Sounds/axiom-chime.wav): python3 tools/make-alarm-sounds.py

Built to wake you up. Full volume from the first second, bright digital tones (like the dot-matrix board):
  0–8 s    the Axiom motif, high-low-higher (G6, E6, C7), twice, then four fast beeps; every 1.6 s
  8–16 s   the same, quicker (every 1.2 s), with an octave on the beeps
  16–28 s  urgent: the motif and beeps back to back (every 0.9 s), doubled an octave up
28 s long (iOS plays up to 30 s, then repeats it until you stop or snooze).
The dashboard plays the same schedule with Web Audio for the preview (alPlay in web/index.html)."""
import math, wave, os, array

RATE = 22050
LEN = 28.0
MOTIF = [1567.98, 1318.51, 2093.00]   # G6, E6, C7
BEEP = 2637.02                       # E7

def events():
    out, t = [], 0.0
    while t < LEN:
        stage = 0 if t < 8 else 1 if t < 16 else 2
        period = (1.6, 1.2, 0.9)[stage]
        step = (.11, .095, .08)[stage]
        x = t
        for rep in range(2 if stage < 2 else 1):
            for f in MOTIF:
                out.append((x, step * .85, f, stage)); x += step
            x += step * .5
        for k in range(4):
            out.append((x, .05, BEEP, stage)); x += .085
        t += period
    return out

def tone(f, x, dur, stage):
    if x < 0 or x > dur: return 0.0
    e = min(1.0, x / .004, (dur - x) / .008)
    # square-ish: odd harmonics, a little rounded so it is loud but not harsh
    v = math.sin(2*math.pi*f*x) + .33*math.sin(2*math.pi*3*f*x) + .15*math.sin(2*math.pi*5*f*x)
    if stage >= 1: v += .45 * math.sin(2*math.pi*2*f*x)
    return e * v

def render():
    n = int(RATE * LEN); s = [0.0] * n
    for start, dur, f, stage in events():
        i0 = int(start * RATE)
        for i in range(i0, min(n, i0 + int(dur * RATE) + 2)):
            s[i] += tone(f, (i - i0) / RATE, dur, stage)
    peak = max(abs(v) for v in s)
    return [v / peak * .97 for v in s]

out = os.path.join(os.path.dirname(__file__), '..', 'App', 'Sounds')
os.makedirs(out, exist_ok=True)
data = array.array('h', (int(v * 32767) for v in render()))
with wave.open(os.path.join(out, 'axiom-chime.wav'), 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(data.tobytes())
print('axiom-chime.wav', len(data) / RATE, 's')
