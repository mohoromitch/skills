"""Inspect a built PDF: page count, fonts, find pages by text, render pages to PNG.

Run with: uv run --with pymupdf python inspect.py FILE.pdf [--find TEXT ...] [--render N ...] [--zoom Z] [--outdir DIR]
"""
import argparse, os, sys
import pymupdf as fitz

ap = argparse.ArgumentParser()
ap.add_argument("pdf")
ap.add_argument("--find", action="append", default=[])
ap.add_argument("--render", action="append", type=int, default=[])
ap.add_argument("--render-find", action="append", default=[])
ap.add_argument("--zoom", type=float, default=1.3)
ap.add_argument("--outdir", default="/tmp/pdf-pages")
a = ap.parse_args()

doc = fitz.open(a.pdf)
r = doc[0].rect
print(f"pages={doc.page_count} size={r.width/72*25.4:.0f}x{r.height/72*25.4:.0f}mm toc_entries={len(doc.get_toc())}")
fonts = set()
for p in doc:
    for f in p.get_fonts():
        fonts.add(f[3])
print("fonts:", sorted(fonts))
for t in a.find:
    hits = [i + 1 for i, p in enumerate(doc) if p.search_for(t)]
    print(f"find {t!r}: pages {hits}")
for t in a.render_find:
    hits = [i + 1 for i, p in enumerate(doc) if p.search_for(t)]
    if hits:
        a.render.append(hits[-1])
        print(f"render-find {t!r}: page {hits[-1]}")
os.makedirs(a.outdir, exist_ok=True)
stem = os.path.splitext(os.path.basename(a.pdf))[0][:40]
for n in a.render:
    pix = doc[n - 1].get_pixmap(matrix=fitz.Matrix(a.zoom, a.zoom))
    out = f"{a.outdir}/{stem}-p{n:03d}.png"
    pix.save(out)
    print("rendered", out)
