"""Illustrative mock-up: the same painted patch at 2, 4 and 8 splat layers.

Usage: python3 tools/terrain_paint_bench/layer_mockup.py OUT.png  (needs numpy, scipy, Pillow)

Not engine output. Weights live at 4 texels per cell and are bilinearly upsampled; layers
combine by height blend (each material's own height map + its weight, sharpest wins), which
is the transition style proposed for the terrain shader.
"""
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import gaussian_filter, zoom

CELLS_X, CELLS_Z = 32, 20
TPC = 4              # weight texels per cell
PX = 16              # rendered pixels per cell
W, H = CELLS_X * PX, CELLS_Z * PX
rng = np.random.default_rng(7)


def noise(scale, shape=(H, W), seed=None):
    r = np.random.default_rng(seed) if seed is not None else rng
    n = gaussian_filter(r.random(shape), scale)
    n -= n.min()
    return n / max(n.max(), 1e-6)


yy, xx = np.mgrid[0:H, 0:W].astype(float)

# ---- material textures (albedo + blend height), stylized ----
def tex(base, var, pattern):
    col = np.array(base, float)[None, None, :] / 255.0
    return np.clip(col * (1 + var[..., None]) + pattern[..., None], 0, 1)

grain = noise(1.2) - 0.5
mid = noise(5) - 0.5
big = noise(14) - 0.5

def grass(c=(98, 140, 62)):
    return tex(c, 0.35 * mid + 0.25 * grain, 0.05 * (grain > 0.18)), 0.4 + 0.5 * noise(1.5)
def moss(c=(70, 110, 72)):
    return tex(c, 0.3 * big + 0.2 * grain, 0.0 * grain), 0.5 + 0.4 * noise(3)
def dirt(c=(122, 92, 62)):
    return tex(c, 0.25 * mid + 0.2 * grain, 0.0 * grain), 0.3 + 0.4 * noise(4)
def gravel(c=(128, 120, 108)):
    dots = (noise(0.9) > 0.62) * 0.12
    return tex(c, 0.15 * grain, dots), 0.35 + 0.6 * noise(0.9)
def sand(c=(196, 176, 128)):
    rip = 0.04 * np.sin((xx * 0.35 + yy * 0.9) + 6 * mid)
    return tex(c, 0.12 * mid, rip), 0.2 + 0.3 * noise(6)
def rock(c=(118, 112, 106)):
    cracks = -0.18 * (np.abs(noise(3) - 0.5) < 0.03)
    return tex(c, 0.3 * mid + 0.15 * grain, cracks), 0.6 + 0.4 * noise(3)
def plating(c=(132, 140, 148)):
    seam = ((xx % 32 < 1.2) | (yy % 32 < 1.2)) * -0.22
    rivet = (((xx % 32 - 4) ** 2 + (yy % 32 - 4) ** 2) < 2.5) * 0.15
    panel = 0.06 * (((xx // 32) + (yy // 32)) % 2)
    return tex(c, 0.05 * grain + panel, seam + rivet), 0.95 + 0.05 * noise(2)
def scorch(c=(48, 42, 38)):
    return tex(c, 0.4 * mid, 0.0 * grain), 0.55 + 0.4 * noise(2.5)

# ---- the painting, authored once at weight resolution (cells * TPC) ----
gx, gz = CELLS_X * TPC, CELLS_Z * TPC
u, v = np.mgrid[0:gz, 0:gx].astype(float)
u /= TPC; v /= TPC                        # now in cells (row, col)
wob = zoom(noise(3, (gz, gx), seed=3), 1) - 0.5

def disc(cz, cx, r, soft=1.0):
    d = np.hypot(u - cz, v - cx) + 2.5 * wob
    return np.clip((r - d) / soft, 0, 1)

def rect(z0, z1, x0, x1, soft=0.6):
    dz = np.maximum(z0 - u, u - z1); dx = np.maximum(x0 - v, v - x1)
    return np.clip(-np.maximum(dz, dx) / soft + 0.5, 0, 1)

paint = {}
paint["grass"] = np.ones((gz, gx))
paint["moss"] = disc(4, 6, 4.5, 2.0) + disc(15, 27, 3.5, 2.0)
paint["dirt"] = np.clip(disc(10, 16, 8.0, 2.5) - rect(6, 13, 11, 21), 0, 1)
road = np.clip(1.2 - np.abs(u - (10 + 0.12 * (v - 16) + 1.5 * np.sin(v * 0.25))) / 1.1, 0, 1) * (v > 20)
paint["dirt"] = np.maximum(paint["dirt"], road)
paint["gravel"] = np.clip(1.4 - np.abs(np.abs(u - (10 + 0.12 * (v - 16) + 1.5 * np.sin(v * 0.25))) - 1.5) / 0.7, 0, 1) * (v > 20)
paint["sand"] = np.clip((u - 16.5) / 1.5 + 1.5 * wob, 0, 1)
paint["rock"] = disc(2, 29, 6.0, 1.2)
paint["plating"] = rect(6.5, 12.5, 11.5, 20.5)
paint["scorch"] = disc(14, 13, 2.2, 1.5) + disc(5, 20, 1.6, 1.2)

def up(a):
    return np.clip(zoom(a, PX / TPC, order=1)[:H, :W], 0, 1)

MATS8 = {"grass": grass(), "moss": moss(), "dirt": dirt(), "gravel": gravel(),
         "sand": sand(), "rock": rock(), "plating": plating(), "scorch": scorch()}

def blend(layers):
    """Height blend: score = blend height + weight; keep what is within `depth` of the best."""
    depth = 0.18
    scores = {k: hmap + 1.6 * w for k, (alb, hmap, w) in layers.items()}
    best = np.max(np.stack(list(scores.values())), 0)
    out = np.zeros((H, W, 3)); tot = np.zeros((H, W))
    for k, (alb, hmap, w) in layers.items():
        f = np.clip(scores[k] - best + depth, 0, None) * (w > 0.02)
        out += alb * f[..., None]; tot += f
    return out / np.maximum(tot, 1e-6)[..., None]

def shade(img):
    hgt = noise(10, seed=11) * 6 + noise(3, seed=12)
    gy, gxx = np.gradient(hgt)
    light = np.clip(1 + 0.9 * (-gxx - gy), 0.7, 1.25)
    return np.clip(img * light[..., None], 0, 1)

def render(assign, mats):
    """`assign` maps each painted stroke name to the material slot that renders it."""
    w = {}
    for stroke, slot in assign.items():
        w[slot] = np.maximum(w.get(slot, 0), up(paint[stroke]))
    order = ["grass", "moss", "dirt", "gravel", "sand", "scorch", "rock", "plating"]
    # later strokes cover earlier ones, like painting
    cover = np.zeros((H, W)); final = {}
    for s in reversed([s for s in order if s in w]):
        final[s] = w[s] * (1 - cover); cover = np.clip(cover + w[s], 0, 1)
    layers = {s: (mats[s][0], mats[s][1], final[s]) for s in final}
    return shade(blend(layers))

eight = render({k: k for k in paint}, MATS8)
four = render({"grass": "grass", "moss": "grass", "dirt": "dirt", "gravel": "dirt",
               "scorch": "dirt", "sand": "dirt", "rock": "rock", "plating": "plating"}, MATS8)
# Same 4 slots, a second map's palette from a larger catalog (arid world, different star)
ARID = {"grass": grass((150, 132, 70)), "dirt": dirt((158, 86, 54)),
        "rock": rock((176, 158, 132)), "plating": plating((96, 132, 128))}
four_b = render({"grass": "grass", "moss": "grass", "dirt": "dirt", "gravel": "dirt",
                 "scorch": "dirt", "sand": "dirt", "rock": "rock", "plating": "plating"}, ARID)
two = render({"grass": "grass", "moss": "grass", "dirt": "dirt", "gravel": "dirt",
              "scorch": "dirt", "sand": "dirt", "rock": "dirt", "plating": "dirt"}, MATS8)

def to_img(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))

panels = [(two, "2 layers  (grass, dirt)"),
          (four, "4 layers  (grass, dirt, rock, plating)  — 1 weight image"),
          (eight, "8 layers  (+ moss, gravel, sand, scorch)  — 2 weight images"),
          (four_b, "4 layers, another map's palette from a catalog")]
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
except OSError:
    font = ImageFont.load_default()
pad, cap = 10, 26
sheet = Image.new("RGB", (W + 2 * pad, len(panels) * (H + cap + pad) + pad), (24, 24, 26))
d = ImageDraw.Draw(sheet)
for i, (a, label) in enumerate(panels):
    y = pad + i * (H + cap + pad)
    d.text((pad, y + 4), label, fill=(230, 230, 230), font=font)
    sheet.paste(to_img(a), (pad, y + cap))
out = sys.argv[1] if len(sys.argv) > 1 else "splat_layer_counts.png"
sheet.save(out)
print(out, sheet.size)
