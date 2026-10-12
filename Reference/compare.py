#!/usr/bin/env python3
"""Referenz (1×-Ausschnitt aus notes-big.png) | App | Differenz → /tmp/mln/cmp.png. Aufruf: compare.py app.png [x0 y0 x1 y1 zoom]"""
import sys, numpy as np
from PIL import Image, ImageChops
ref = Image.open('/Users/maik/Downloads/Moutain Lion Notes/notes-big.png').convert('RGB').crop((42, 25, 778, 468))
app = Image.open(sys.argv[1]).convert('RGB')
box = tuple(int(v) for v in sys.argv[2:6]) if len(sys.argv) > 5 else (0, 0, 736, 443)
z = int(sys.argv[6]) if len(sys.argv) > 6 else 1
r, a = ref.crop(box), app.crop(box)
d = ImageChops.difference(r, a)
n = np.asarray(d).max(axis=2); print('>8/255: %.1f%%  mittl. Abw. %.1f' % ((n > 8).mean() * 100, n.mean()))
W, H = r.size; out = Image.new('RGB', (W * z, H * z * 3 + 8))
for i, im in enumerate((r, a, d.point(lambda v: min(255, v * 4)))): out.paste(im.resize((W * z, H * z), Image.NEAREST), (0, i * (H * z + 4)))
out.save('/tmp/mln/cmp.png')
