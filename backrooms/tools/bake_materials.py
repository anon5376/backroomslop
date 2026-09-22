#!/usr/bin/env python3
"""Original seamless PBR surface generator (numpy + Pillow). No external assets."""
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / 'assets/materials'
N = 1024
RNG = np.random.default_rng(314159)
y, x = np.mgrid[:N, :N] / N


def band(scale):
    f = np.fft.fftfreq(N) * N
    spectrum = np.fft.fft2(RNG.normal(size=(N, N)))
    spectrum *= np.exp(-(f[:, None]**2 + f[None, :]**2) / (2*scale**2))
    a = np.fft.ifft2(spectrum).real
    return a / max(a.std(), 1e-6)


def save(name, color, height, roughness, strength=3):
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1))*strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0))*strength
    normal = np.stack([-dx, dy, np.ones_like(dx)], axis=-1)
    normal /= np.linalg.norm(normal, axis=-1)[..., None]
    maps = {'albedo': np.clip(color,0,1), 'normal': normal*0.5+0.5,
            'roughness': np.clip(roughness,0,1)}
    for kind, data in maps.items():
        assert np.isfinite(data).all()
        Image.fromarray(np.round(data*255).astype('uint8')).save(ROOT/f'{name}_{kind}.png')
    print(name, '3 maps', N, 'x', N)


def bake():
    ROOT.mkdir(parents=True,exist_ok=True)
    fine = band(220)
    wear = band(5)
    # Embossed ogee/leaf repeat: color and relief derive from the same motif.
    u, v = (x*8)%1, (y*8)%1
    leaf = np.exp(-((np.abs(u-.5)-.20*np.sin(np.pi*v))/.022)**2)
    stem = np.exp(-((u-.5)/.016)**2)*(0.3+0.7*np.sin(np.pi*v)**2)
    emboss = np.maximum(leaf, stem)
    for name,base in [('wall',(0.64,.55,.32)),('wall_b',(.49,.47,.28))]:
        tint = 1 + wear*.018 + fine*.008 - emboss*.085
        color = np.array(base)*tint[...,None]
        height = emboss*.10 + fine*.009
        save(name,color,height,.86+fine*.014+wear*.008,3)
    # Tiny crossed fiber bundles, directional pile and low contrast wear.
    fiber = np.sin(2*np.pi*(x*192+0.035*np.sin(y*2*np.pi*64)))
    fiber *= np.sin(2*np.pi*y*256)
    pile = band(100)*.035 + fine*.027 + fiber*.024
    color = np.array([.34,.285,.18])*(1+pile*2+wear*.025)[...,None]
    save('carpet',color,pile,.95+fine*.008,2)
    # Four acoustic tiles per repeat with recessed seams and pinholes.
    seam = (((x*4)%1<.012)|((y*4)%1<.012)).astype(float)
    pinholes = (band(150)>1.75).astype(float)
    height = -seam*.22-pinholes*.06+fine*.008
    color = np.array([.72,.70,.64])*(1-seam*.24-pinholes*.15+fine*.012+wear*.012)[...,None]
    save('ceiling',color,height,.92+fine*.01,3)
    pores = np.maximum(band(170)-1.4,0)
    joints = ((y*2)%1<.008).astype(float)
    height = fine*.015-pores*.05-joints*.16
    save('concrete',np.array([.43,.445,.425])*(1+wear*.04+fine*.025-pores*.035-joints*.16)[...,None],height,.82+wear*.025,3)
    seams = (((x*4)%1<.015)|((y*4)%1<.015)).astype(float)
    slots = (((y*16)%1<.12)&((x*4)%1>.15)&((x*4)%1<.85)).astype(float)
    height = -seams*.18-slots*.08+fine*.002
    save('server',np.array([.14,.165,.19])*(1-seams*.35-slots*.20+fine*.018)[...,None],height,.46+fine*.025,3)
    grid = (((x*4)%1<.012)|((y*4)%1<.012)).astype(float)
    save('floor_server',np.array([.105,.12,.13])*(1-grid*.38+fine*.035)[...,None],-grid*.14+fine*.003,.59+fine*.018,2)


if __name__ == '__main__':
    bake()
