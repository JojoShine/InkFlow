"""Generate short original typing sounds: python3 tool/generate_typing_sounds.py."""
import math
import random
import struct
import wave
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "assets" / "sounds"
root.mkdir(parents=True, exist_ok=True)
rate = 44100
for name, duration in [("soft", .035), ("mechanical", .065), ("typewriter", .12)]:
    rng = random.Random(42)
    values = []
    for index in range(round(rate * duration)):
        t = index / rate
        noise = rng.uniform(-1, 1)
        attack = min(1, t / .0008)
        if name == "soft":
            value = attack * math.exp(-t * 145) * (.5 * noise + .3 * math.sin(2 * math.pi * 460 * t))
        elif name == "mechanical":
            value = attack * math.exp(-t * 90) * (.7 * noise + .25 * math.sin(2 * math.pi * 1800 * t))
            if t > .023:
                value += .25 * noise * math.exp(-(t - .023) * 180)
        else:
            value = attack * math.exp(-t * 100) * (.6 * noise + .3 * math.sin(2 * math.pi * 2300 * t))
            if t > .027:
                value += math.exp(-(t - .027) * 55) * (.35 * noise + .18 * math.sin(2 * math.pi * 310 * t))
        fade = min(1, (duration - t) / .008)
        values.append(value * fade)
    peak = max(abs(value) for value in values)
    samples = [round(value / peak * 20000) for value in values]
    with wave.open(str(root / f"{name}.wav"), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(struct.pack(f"<{len(samples)}h", *samples))
