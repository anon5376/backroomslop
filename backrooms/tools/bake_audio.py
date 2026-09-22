#!/usr/bin/env python3
"""Bake original deterministic sound design. Requires numpy; no downloaded samples."""
from pathlib import Path
import json
import wave
import numpy as np

RATE = 44100
ROOT = Path(__file__).resolve().parents[1] / 'assets' / 'audio'
RNG = np.random.default_rng(19960314)
REPORT = {}


def noise(n, cutoff=1500, low=20):
    frequencies = np.fft.rfftfreq(n, 1 / RATE)
    spectrum = np.fft.rfft(RNG.normal(0, 1, n))
    spectrum *= 1 / np.sqrt(1 + (frequencies / cutoff) ** 6)
    spectrum *= frequencies / np.sqrt(frequencies ** 2 + low ** 2)
    signal = np.fft.irfft(spectrum, n)
    return signal / max(np.std(signal), 1e-9)


def save(name, signal, peak=0.55, loop=False):
    signal = np.asarray(signal, dtype=float)
    if not loop:
        fade = min(int(RATE * 0.012), len(signal) // 4)
        signal[:fade] *= np.linspace(0, 1, fade).reshape((-1,) + (1,) * (signal.ndim - 1))
        signal[-fade:] *= np.linspace(1, 0, fade).reshape((-1,) + (1,) * (signal.ndim - 1))
    signal -= np.mean(signal, axis=0)
    signal *= peak / max(np.max(np.abs(signal)), 1e-9)
    assert np.isfinite(signal).all() and np.max(np.abs(signal)) < 0.95
    pcm = (signal * 32767).astype('<i2')
    channels = 1 if pcm.ndim == 1 else pcm.shape[1]
    with wave.open(str(ROOT / (name + '.wav')), 'wb') as stream:
        stream.setnchannels(channels)
        stream.setsampwidth(2)
        stream.setframerate(RATE)
        stream.writeframes(pcm.tobytes())
    seam = float(np.max(np.abs(signal[-1] - signal[0])))
    if loop:
        assert seam < 0.025, (name, seam)
    REPORT[name] = dict(seconds=len(pcm) / RATE, channels=channels,
                        peak=float(np.max(np.abs(signal))), rms=float(np.sqrt(np.mean(signal ** 2))),
                        loop=loop, seam_delta=seam)


def bake():
    ROOT.mkdir(parents=True, exist_ok=True)
    # Periodic Fourier noise and integer-cycle partials avoid a spliced loop seam.
    t = np.arange(RATE * 12) / RATE
    hum = sum(a * np.sin(2 * np.pi * f * t + phase) for a, f, phase in
              [(0.8,120,0),(0.19,240,0.7),(0.08,360,1.4),(0.03,720,0.2)])
    hum *= 0.88 + 0.07 * np.sin(2 * np.pi * t / 6) + 0.04 * np.sin(2 * np.pi * t / 3)
    hum += 0.025 * noise(len(t), 900, 100)
    save('hum_loop', hum, 0.34, True)
    t = np.arange(RATE * 24) / RATE
    center = noise(len(t), 280, 25) * 0.16
    for frequency, amplitude in [(42,0.12),(55,0.1),(82.5,0.035),(110,0.018)]:
        center += amplitude * np.sin(2 * np.pi * frequency * t + 0.4 * np.sin(2 * np.pi * t / 24))
    side = noise(len(t), 750, 180) * 0.055 * (0.7 + 0.3 * np.sin(2 * np.pi * t / 12))
    save('drone_loop', np.column_stack([center + side, center - side]), 0.36, True)
    for index in range(6):
        t = np.arange(int(RATE * 0.34)) / RATE
        body = np.sin(2 * np.pi * (65 + index * 3) * t) * np.exp(-t * 31)
        heel = noise(len(t), 500 + index * 35) * np.exp(-t * 30)
        brush = noise(len(t), 2200, 280) * np.exp(-((t - 0.09) / 0.055) ** 2)
        save(f'step_{index}', body * 0.6 + heel * 0.35 + brush * 0.085, 0.48)
    t = np.arange(int(RATE * 0.7)) / RATE
    thunk = sum(a * np.sin(2*np.pi*f*t) * np.exp(-t*d) for a,f,d in
                [(0.7,94,15),(0.3,173,22),(0.13,337,35)])
    thunk += noise(len(t), 1800) * np.exp(-t*100) * 0.3
    save('thunk', thunk, 0.60)
    t = np.arange(RATE * 2) / RATE
    phase = np.cumsum(135 - 42 * t + 13 * np.sin(t * 37)) * 2 * np.pi / RATE
    creak = (np.sin(phase) + 0.25*np.sin(phase*2.17)) * np.sin(np.pi*t/2)**1.4
    creak *= 0.6 + 0.4 * np.sin(t*61)**2
    save('creak', creak + noise(len(t),1700)*0.06*np.sin(np.pi*t/2), 0.48)
    t = np.arange(int(RATE*1.4)) / RATE
    drag = noise(len(t),750,40) * np.sin(np.pi*t/1.4)**1.5
    drag += noise(len(t),3200,1400) * 0.09 * np.sin(np.pi*t/1.4)**2
    save('drag', drag, 0.48)
    t = np.arange(int(RATE*2.1)) / RATE
    phase = 2*np.pi*np.cumsum(360*np.exp(-t*0.25) + 24*np.sin(t*33))/RATE
    envelope = (1-np.exp(-t*28))*np.exp(-t*2)
    screech = (np.sin(phase)+0.4*np.sin(phase*1.487)+noise(len(t),2300)*0.2)*envelope
    save('screech', screech, 0.62)
    t = np.arange(int(RATE*0.65)) / RATE
    gulp = np.zeros_like(t)
    for at, frequency in [(0.08,390),(0.23,300),(0.39,230)]:
        dt = np.maximum(t-at,0)
        gulp += np.sin(2*np.pi*(frequency*dt-130*dt*dt))*np.exp(-dt*28)*(t>=at)
    save('gulp', gulp, 0.42)
    (ROOT / 'manifest.json').write_text(json.dumps(REPORT, indent=2)+'\n')
    print(json.dumps(REPORT, indent=2))


if __name__ == '__main__':
    bake()
