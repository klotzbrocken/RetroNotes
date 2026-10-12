#!/usr/bin/env python3
"""Erzeugt Leder-/Papier-Kacheln (512 px = 256 pt, kachelbar, Graustufen um 128 für Overlay/Soft-Light)
und AppIcon.icns aus Resources/icon-source.png (freigestellt). Aufruf im Projektordner."""
import numpy as np, os, subprocess
from PIL import Image
def field(n, sigma, seed):
    w = np.random.default_rng(seed).standard_normal((n, n))
    if sigma > 0:
        f = np.fft.fftfreq(n)[:, None]**2 + np.fft.fftfreq(n)[None, :]**2
        w = np.fft.ifft2(np.fft.fft2(w) * np.exp(-2 * np.pi**2 * sigma**2 * f)).real
    return (w - w.mean()) / w.std()
def save(name, parts, amp):
    """RGBA-Kachel: Weiß/Schwarz mit Alpha ∝ Rauschen (normales Source-Over, in jeder Ebene korrekt)."""
    n = sum(a * field(512, s, i + 3) for i, (a, s) in enumerate(parts)); n = n / np.abs(n).std()
    rgb = np.where(n > 0, 255, 0).astype(np.uint8)
    al = np.clip(np.abs(n) * amp, 0, 255).astype(np.uint8)
    Image.fromarray(np.dstack([rgb, rgb, rgb, al]), "RGBA").save(f"Resources/{name}.png", dpi=(144, 144))
save("leather", [(26, 0.6), (14, 1.2), (3, 3)], 5)   # Narbung
save("paper", [(14, 0.6), (10, 1.5), (7, 5), (4, 14)], 2.2)      # Fasern
# Icon: auf Quadrat 1024 zentrieren, iconset -> icns
src = Image.open("Resources/icon-source.png").convert("RGBA"); src = src.crop(src.getbbox())
s = 900 / max(src.size); src = src.resize((round(src.width * s), round(src.height * s)), Image.LANCZOS)
sq = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0)); sq.paste(src, ((1024 - src.width) // 2, (1024 - src.height) // 2), src)
os.makedirs("/tmp/mln.iconset", exist_ok=True)
for sz in (16, 32, 128, 256, 512):
    sq.resize((sz, sz), Image.LANCZOS).save(f"/tmp/mln.iconset/icon_{sz}x{sz}.png")
    sq.resize((sz * 2, sz * 2), Image.LANCZOS).save(f"/tmp/mln.iconset/icon_{sz}x{sz}@2x.png")
subprocess.run(["iconutil", "-c", "icns", "/tmp/mln.iconset", "-o", "Resources/AppIcon.icns"], check=True)
