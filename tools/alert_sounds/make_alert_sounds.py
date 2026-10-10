#!/usr/bin/env python3
"""Synthesise the placeholder alert sounds into assets/audio/alerts/.

These are stand-ins, not the game's sound design: plain sine tones with a short envelope, one
per AlertCatalog.Tone, distinct enough to tell apart by ear. Generated rather than downloaded so
they carry no licence at all. Rerun to regenerate after changing a tone below:

    python3 tools/alert_sounds/make_alert_sounds.py

gdd/systems/ux/ui/alerts.md §Presentation.
"""

import math
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parents[2] / "assets" / "audio" / "alerts"

# Each tone: a list of (frequency Hz, start s, length s) notes, mixed and normalised.
TONES = {
    # ROUTINE — one soft, low blip: "something worth knowing".
    "alert_routine": [(660.0, 0.00, 0.18)],
    # WARNING — a rising two-note chime: "look at this".
    "alert_warning": [(740.0, 0.00, 0.14), (988.0, 0.12, 0.20)],
    # URGENT — three quick high pulses: "act now".
    "alert_urgent": [(1175.0, 0.00, 0.09), (1175.0, 0.12, 0.09), (1397.0, 0.24, 0.16)],
    # COMPLETE — a soft falling major third: "done". The generic completion, until purchases
    # have their own.
    "alert_complete": [(880.0, 0.00, 0.12), (698.5, 0.10, 0.22)],
}

PEAK = 0.45  # of full scale; the bus sits at -6 dB and these sit under unit barks


def envelope(t: float, length: float) -> float:
    attack = min(0.01, length / 4)
    release = min(0.08, length / 2)
    if t < attack:
        return t / attack
    if t > length - release:
        return max(0.0, (length - t) / release)
    return 1.0


def render(notes: list[tuple[float, float, float]]) -> list[float]:
    total = max(start + length for _, start, length in notes) + 0.02
    samples = [0.0] * int(total * RATE)
    for freq, start, length in notes:
        first = int(start * RATE)
        for i in range(int(length * RATE)):
            t = i / RATE
            # A touch of the octave makes a sine read as a chime rather than a test tone.
            wave_value = math.sin(2 * math.pi * freq * t) + 0.25 * math.sin(4 * math.pi * freq * t)
            samples[first + i] += wave_value * envelope(t, length)
    peak = max(abs(s) for s in samples) or 1.0
    return [s / peak * PEAK for s in samples]


def write(name: str, samples: list[float]) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))


if __name__ == "__main__":
    for tone_name, tone_notes in TONES.items():
        write(tone_name, render(tone_notes))
        print(f"wrote {OUT / tone_name}.wav")
