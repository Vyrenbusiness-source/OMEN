#!/usr/bin/env python3
"""Erzeugt den eingebauten Skin "Pfeile" (4K-Pfeil-Skin) nach assets_game/skins/Pfeile/.

Eigenes Design. Spalten 1-4 = links, unten, oben, rechts (ein Pfeil-Motiv, gedreht).
Noten/Hold-Kopf/Koerper/Kappe sind NEUTRALE Graustufen (Playfield2D toent sie mit
Takt-/Spalten-/Nutzerfarbe, Multiplikation): weisse Flaeche + dunkle Kante, die
Kante bleibt in jeder Farbe lesbar. Rezeptoren = Pfeil-Umriss, gedrueckt = gefuellt.
Mitte bei 5K-7K = Raute (arrowS/karrowS), Richtungsmuster siehe ManiaSkin.arrow_dir.
Deterministisch, 4x Supersampling. Aufruf:
    python tools/gen_arrow_skin.py
Danach Godot einmal importieren lassen (--headless --import) und *.png.import einchecken.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw, ImageFilter
import gen_mania_skins as g

SS, W = g.SS, g.W
ARROW_COLS = g.ARROW_COLS
DIRS = g.DIRS
PAD = 12
NECK = 0.40


def canvas(w, h):
    return g.canvas(w, h)


def mask_of(pts, size):
    m = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(m).polygon([(x * SS, y * SS) for x, y in pts], fill=255)
    return m


def diamond_poly(size, pad=PAD):
    c = size / 2
    r = size / 2 - pad
    return [(c, c - r), (c + r, c), (c, c + r), (c - r, c)]


def shape(kind, size=W):
    pts = diamond_poly(size) if kind == "S" else g.arrow_poly(kind, size, PAD, NECK)
    return mask_of(pts, size)


def erode(m, px):
    k = int(px * SS) * 2 + 1
    return m.filter(ImageFilter.MinFilter(k))


def layer(mask, v, a=255):
    im = Image.new("RGBA", mask.size, (v, v, v, 0))
    im.putalpha(mask.point(lambda p: a if p else 0))
    return im


def note(kind, size=W):
    """Graustufen-Note: dunkle Kante, helle Flaeche, feine Innenlinie (Kante auch bei Farbe klar)."""
    outer = shape(kind, size)
    rim = erode(outer, 4)
    core = erode(outer, 9)
    im = layer(outer, 70)
    im.alpha_composite(layer(rim, 150))
    im.alpha_composite(layer(core, 255))
    return g.finish(im, size, size)


def receptor(kind, pressed, c, size=W):
    outer = shape(kind, size)
    ring = erode(outer, 7)
    im = Image.new("RGBA", outer.size, (0, 0, 0, 0))
    base = g.mix(c, (0, 0, 0), 0.55)
    if pressed:
        fill = Image.new("RGBA", outer.size, g.rgba(g.mix(c, (255, 255, 255), 0.25), 0))
        fill.putalpha(outer.point(lambda p: 215 if p else 0))
        im.alpha_composite(fill)
        inner = Image.new("RGBA", outer.size, g.rgba(g.mix(c, (255, 255, 255), 0.55), 0))
        inner.putalpha(erode(outer, 11).point(lambda p: 150 if p else 0))
        im.alpha_composite(inner)
    else:
        ol = Image.new("RGBA", outer.size, g.rgba(c, 0))
        ol.putalpha(outer.point(lambda p: 215 if p else 0))
        im.alpha_composite(ol)
        hole = Image.new("RGBA", outer.size, g.rgba(base, 0))
        hole.putalpha(ring.point(lambda p: 235 if p else 0))
        # Loch ausstanzen, dann dunkle Fuellung (deckend genug fuer Lesbarkeit der Noten darueber)
        a = im.split()[3]
        a.paste(0, mask=ring)
        im.putalpha(a)
        im.alpha_composite(hole)
    return g.finish(im, size, size)


def hold_body(w=W, h=16):
    im = canvas(w, h)
    d = ImageDraw.Draw(im)
    nx = w / 2 - (w / 2 - PAD) * NECK
    x0, x1 = nx * SS, (w - nx) * SS
    d.rectangle((x0, 0, x1, h * SS), fill=(70, 70, 70, 235))
    d.rectangle((x0 + 4 * SS, 0, x1 - 4 * SS, h * SS), fill=(190, 190, 190, 235))
    d.rectangle((x0 + 9 * SS, 0, x1 - 9 * SS, h * SS), fill=(235, 235, 235, 235))
    return g.finish(im, w, h)


def hold_tail(w=W, h=24):
    im = canvas(w, h)
    d = ImageDraw.Draw(im)
    nx = w / 2 - (w / 2 - PAD) * NECK
    for inset, v in ((0, 70), (4, 190), (9, 235)):
        d.rounded_rectangle(((nx + inset) * SS, -20 * SS, (w - nx - inset) * SS, (14 - inset * 0.5) * SS),
                            radius=max(2, 6 - inset // 3) * SS, fill=(v, v, v, 235))
    return g.finish(im, w, h)


def main():
    imgs = {}
    for kind, nm in list(zip(DIRS, range(4))) + [("S", "S")]:
        base = "mania-arrow%s" % nm
        n = note(kind)
        imgs[base] = n
        imgs[base + "H"] = n
        imgs[base + "L"] = hold_body()
        imgs[base + "T"] = hold_tail()
        c = ARROW_COLS[nm] if nm != "S" else (242, 181, 68)
        imgs["mania-karrow%s" % nm] = receptor(kind, False, c)
        imgs["mania-karrow%sD" % nm] = receptor(kind, True, c)
    lines = []
    for col in range(4):
        lines += ["NoteImage%d: mania-arrow%d" % (col, col), "KeyImage%d: mania-karrow%d" % (col, col),
                  "KeyImage%dD: mania-karrow%dD" % (col, col)]
    imgs.update(g.stage_images((76, 82, 104), (160, 168, 196)))
    g.write_skin("Pfeile", "Pfeile", lines, imgs, ARROW_COLS)
    p = os.path.join(g.OUT, "Pfeile", "skin.ini")
    t = open(p).read().replace("Tint: 1\n", "Tint: 1\nLayout: arrows\n")
    open(p, "w", newline="\n").write(t)


if __name__ == "__main__":
    main()
