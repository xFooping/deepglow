"""Synthesizes the sounds Kenney's packs don't cover: a calm ambient music loop, a cave ambience
loop (wind and drips) and a soft steam hiss. Pure Python, no dependencies.
These files are generated for this project and released as CC0 like the rest of the placeholders.

Run:  python tools/gen_audio.py
"""
import math
import os
import random
import struct
import wave

ROOT = os.path.join(os.path.dirname(__file__), "..")
RATE = 22050


def write_wav(path, samples):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    peak = max(1e-6, max(abs(s) for s in samples))
    scale = 0.85 / peak
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples))
    print("wrote", os.path.relpath(path, ROOT), f"{len(samples) / RATE:.1f}s")


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


def music_loop(seconds=32.0):
    """Warm pad chords with a slow, sparse pentatonic pluck melody. Loops seamlessly."""
    n = int(seconds * RATE)
    out = [0.0] * n
    chords = [[50, 57, 62, 66, 69], [47, 54, 59, 62, 66], [43, 50, 55, 59, 62], [45, 52, 57, 61, 64]]  # Dmaj9, Bm7, Gmaj7, A
    seg = n // len(chords)
    fade = int(1.5 * RATE)
    for ci, chord in enumerate(chords):
        start = ci * seg
        for note in chord:
            f = midi(note)
            for k in range(-fade, seg + fade):
                i = (start + k) % n
                # crossfaded window so chord changes (and the loop seam) are smooth
                if k < fade:
                    env = 0.5 - 0.5 * math.cos(math.pi * (k + fade) / (2 * fade))
                elif k > seg - fade:
                    env = 0.5 + 0.5 * math.cos(math.pi * (k - (seg - fade)) / (2 * fade))
                else:
                    env = 1.0
                t = (start + k) / RATE
                v = math.sin(2 * math.pi * f * t) + 0.5 * math.sin(2 * math.pi * f * 1.003 * t) + 0.15 * math.sin(4 * math.pi * f * t)
                out[i] += 0.05 * env * v
    rng = random.Random(7)
    scale = [62, 64, 66, 69, 71, 74, 76, 78]
    t = 0.6
    while t < seconds - 1.5:
        note = rng.choice(scale)
        f = midi(note)
        start = int(t * RATE)
        for k in range(int(1.6 * RATE)):
            i = start + k
            if i >= n:
                break
            tt = k / RATE
            env = math.exp(-tt * 3.0) * min(1.0, tt * 200)
            v = math.sin(2 * math.pi * f * tt) + 0.3 * math.sin(4 * math.pi * f * tt)
            out[i] += 0.12 * env * v
            j = i + int(0.375 * RATE)  # one soft echo
            if j < n:
                out[j] += 0.05 * env * v
        t += rng.choice([1.0, 1.5, 2.0, 2.5])
    return out


def cave_ambience(seconds=20.0):
    """Low filtered wind plus occasional water drips. Loops seamlessly."""
    n = int(seconds * RATE)
    rng = random.Random(11)
    out = [0.0] * n
    lp = 0.0
    for i in range(n):
        lp += 0.02 * (rng.uniform(-1, 1) - lp)
        swell = 0.6 + 0.4 * math.sin(2 * math.pi * i / n * 2)
        out[i] = lp * 3.0 * swell
    t = 0.5
    while t < seconds - 0.5:
        f0 = rng.uniform(900, 1600)
        start = int(t * RATE)
        for k in range(int(0.25 * RATE)):
            tt = k / RATE
            f = f0 * (1.0 + 0.8 * math.exp(-tt * 40))
            out[(start + k) % n] += 0.35 * math.exp(-tt * 18) * math.sin(2 * math.pi * f * tt)
        t += rng.uniform(1.2, 3.5)
    return out


def steam_hiss(seconds=0.35):
    rng = random.Random(3)
    n = int(seconds * RATE)
    out = []
    prev = 0.0
    for i in range(n):
        x = rng.uniform(-1, 1)
        hp = x - prev  # crude high-pass for a hiss
        prev = x
        env = min(1.0, i / (0.02 * RATE)) * math.exp(-i / RATE * 9)
        out.append(hp * env)
    return out


write_wav(os.path.join(ROOT, "audio", "music", "deepglow_ambient.wav"), music_loop())
write_wav(os.path.join(ROOT, "audio", "music", "cave_ambience.wav"), cave_ambience())
write_wav(os.path.join(ROOT, "audio", "sfx", "water_hiss.wav"), steam_hiss())
