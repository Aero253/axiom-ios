"""Makes Axiom's alarm sounds (App/Sounds/*.wav): python3 tools/make-alarm-sounds.py
Each is 28 s (iOS plays up to 30 s of a custom alarm sound) of a pattern that repeats.
The dashboard plays the same patterns with Web Audio for the preview, so keep the two in step."""
import math, struct, wave, os, array

RATE = 22050
LEN = 28.0
out = os.path.join(os.path.dirname(__file__), '..', 'App', 'Sounds')

def write(name, samples):
    peak = max(1e-9, max(abs(x) for x in samples))
    data = array.array('h', (int(max(-1, min(1, x / peak * .89)) * 32767) for x in samples))
    with wave.open(os.path.join(out, name), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(data.tobytes())
    print(name, len(samples) / RATE, 's')

def env(t, start, dur, a=.004, r=.012):
    if t < start or t > start + dur: return 0.0
    x = t - start
    return min(1.0, x / a, (dur - x) / r) if dur > 0 else 0

def beep():   # the classic digital alarm clock: four quick beeps, a pause, again
    n = int(RATE * LEN); s = [0.0] * n; period = 1.0
    for i in range(n):
        t = i / RATE; p = t % period; v = 0.0
        for k in range(4):
            e = env(p, k * .125, .075)
            if e: v = e * (math.sin(2 * math.pi * 2048 * t) + .3 * math.sin(2 * math.pi * 6144 * t))
        s[i] = v
    return s

def chime():  # a rising bell arpeggio that comes round every two seconds
    n = int(RATE * LEN); s = [0.0] * n; notes = [523.25, 659.25, 783.99, 1046.5]
    for i in range(n):
        t = i / RATE; p = t % 2.0; v = 0.0
        for k, f in enumerate(notes):
            x = p - k * .18
            if x >= 0: v += math.exp(-x * 3.2) * (math.sin(2 * math.pi * f * x) + .25 * math.sin(2 * math.pi * f * 2.76 * x) * math.exp(-x * 6)) * min(1, x / .003)
        s[i] = v
    return s

def buzz():   # the ticker's caution alert as a sound: a two-tone klaxon, on and off
    n = int(RATE * LEN); s = [0.0] * n
    for i in range(n):
        t = i / RATE; p = t % 1.2
        e = env(p, 0, .7, .01, .03)
        if e:
            f = 520 if (p % .35) < .175 else 440
            ph = (t * f) % 1.0
            s[i] = e * (2 * ph - 1) * .8 + e * .4 * math.sin(2 * math.pi * f * 2 * t)
    return s

os.makedirs(out, exist_ok=True)
write('axiom-beep.wav', beep())
write('axiom-chime.wav', chime())
write('axiom-buzz.wav', buzz())
