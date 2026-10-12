#!/usr/bin/env python3
"""Löst das Gemini-Icon (weißer Hintergrund, weicher Schatten) frei → Resources/icon-source.png.
Aufruf: cutout_icon.py <bild.jpeg>   Neutral-graue Pixel (Hintergrund/Schatten) werden zu schwarz mit Alpha ∝ Dunkelheit, das gelbe Papier bleibt deckend."""
import sys, numpy as np
from collections import deque
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB'); a = np.asarray(im).astype(float)
mx, mn = a.max(axis=2), a.min(axis=2)
cand = ((mx - mn) < 14) & (mn > 120)            # kaum Farbsättigung = Hintergrund/Schatten
def shift(m, dy, dx, fill):
    o = np.full_like(m, fill); H, W = m.shape
    o[max(dy,0):H+min(dy,0), max(dx,0):W+min(dx,0)] = m[max(-dy,0):H+min(-dy,0), max(-dx,0):W+min(-dx,0)]; return o
def erode(m, r=10):          # dünne Verbindungen (Rissband-Enden) kappen
    for _ in range(r):
        m = m & shift(m,1,0,True) & shift(m,-1,0,True) & shift(m,0,1,True) & shift(m,0,-1,True)
    return m
def dilate(m, r=10):
    for _ in range(r):
        m = m | shift(m,1,0,False) | shift(m,-1,0,False) | shift(m,0,1,False) | shift(m,0,-1,False)
    return m
full = cand; cand = erode(cand)
H, W = cand.shape                                  # nur der mit dem Rand verbundene Bereich (das weiße Rissband im Papier bleibt)
flat = cand.ravel(); seen = np.zeros(H * W, bool); q = deque()
for i in list(range(W)) + list(range((H - 1) * W, H * W)) + list(range(0, H * W, W)) + list(range(W - 1, H * W, W)):
    if flat[i] and not seen[i]: seen[i] = True; q.append(i)
while q:
    i = q.popleft(); x = i % W
    for j in (i - W, i + W, i - 1 if x else -1, i + 1 if x < W - 1 else -1):
        if 0 <= j < H * W and flat[j] and not seen[j]: seen[j] = True; q.append(j)
neutral = dilate(seen.reshape(H, W)) & full
dark = np.clip((255 - mn) / 255 * 1.15, 0, 1)
alpha = np.where(neutral, dark, 1.0)
rgb = np.where(neutral[..., None], 0, a)
out = np.dstack([rgb, alpha * 255]).astype('uint8')
Image.fromarray(out, 'RGBA').save('Resources/icon-source.png'); print(Image.fromarray(out, 'RGBA').getchannel('A').getbbox())
