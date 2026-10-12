#!/usr/bin/env python3
"""Komponentenvergleich App-Snapshot vs. 1×-Referenz (notes-big.png): Anteil Pixel >8/255 roh und bei bester Ausrichtung (±3 px)."""
import sys, numpy as np
from PIL import Image
ref = np.asarray(Image.open('/Users/maik/Downloads/Moutain Lion Notes/notes-big.png').convert('RGB').crop((42, 25, 778, 468))).astype(int)
app = np.asarray(Image.open(sys.argv[1]).convert('RGB')).astype(int)
C = {'Titelleiste': (0, 0, 736, 23), 'Seitenleiste': (0, 24, 130, 443), 'Suchfeld': (143, 35, 359, 57), 'Liste': (143, 69, 359, 405),
     'Untere Knöpfe': (143, 413, 359, 435), 'Papier-Kopf/Riss': (373, 22, 736, 60), 'Papiertext': (373, 60, 736, 300), 'Papier unten': (373, 400, 736, 443), 'Gesamt': (0, 0, 736, 443)}
def score(a, r): return (np.abs(a - r).max(axis=2) > 8).mean() * 100
print('%-18s %8s %10s %8s' % ('Komponente', 'roh %', 'best %', 'Versatz'))
for n, (x0, y0, x1, y1) in C.items():
    r = ref[y0:y1, x0:x1]; raw = score(app[y0:y1, x0:x1], r); best = (raw, (0, 0))
    for dy in range(-3, 4):
        for dx in range(-3, 4):
            if y0 + dy < 0 or x0 + dx < 0 or y1 + dy > 443 or x1 + dx > 736: continue
            s = score(app[y0 + dy:y1 + dy, x0 + dx:x1 + dx], r)
            if s < best[0]: best = (s, (dx, dy))
    print('%-18s %8.1f %10.1f %8s' % (n, raw, best[0], best[1]))
