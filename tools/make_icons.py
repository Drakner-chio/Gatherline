#!/usr/bin/env python3
"""Makes the action icons in media/icons/ (white line drawings on transparent, 64x64 TGA;
the game tints them). Usage: make_icons.py"""
import math, os
from PIL import Image, ImageDraw
S, OUT = 256, 64
W = 20  # line width at 256
here = os.path.join(os.path.dirname(__file__), "..", "media", "icons")
os.makedirs(here, exist_ok=True)

def new():
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)

def line(d, pts, w=W):
    d.line(pts, fill="white", width=w, joint="curve")
    for p in (pts[0], pts[-1]):
        d.ellipse([p[0]-w/2, p[1]-w/2, p[0]+w/2, p[1]+w/2], fill="white")

def head(d, tip, ang, size=46):
    a1, a2 = ang + math.radians(150), ang - math.radians(150)
    p1 = (tip[0] + size*math.cos(a1), tip[1] + size*math.sin(a1))
    p2 = (tip[0] + size*math.cos(a2), tip[1] + size*math.sin(a2))
    line(d, [p1, tip, p2])

def save(im, name):
    im.resize((OUT, OUT), Image.LANCZOS).save(os.path.join(here, name + ".tga"))

# turn round: two opposite arrows
im, d = new()
line(d, [(52, 92), (200, 92)]); head(d, (204, 92), 0)
line(d, [(204, 164), (56, 164)]); head(d, (52, 164), math.pi)
save(im, "reverse")

# share: box with an arrow out of it
im, d = new()
line(d, [(150, 70), (70, 70), (70, 196), (196, 196), (196, 116)])
line(d, [(118, 148), (204, 62)]); head(d, (206, 60), -math.pi/4)
save(im, "share")

# edit: pencil
im, d = new()
line(d, [(70, 186), (176, 80)], 44)
im2, d2 = new()
d2.line([(70, 186), (176, 80)], fill="white", width=44)
d.polygon([(48, 208), (60, 162), (94, 196)], fill="white")
im = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
d.line([(86, 170), (178, 78)], fill="white", width=40)
d.polygon([(52, 204), (64, 156), (100, 192)], fill="white")
d.line([(186, 70), (200, 56)], fill="white", width=40)
save(im, "edit")

# direction: a loop ridden clockwise (cw) or anticlockwise (ccw), a filled arrowhead at its end
def tri(d, at, ang, length=52, half=30):
    ux, uy = math.cos(ang), math.sin(ang)
    tip = (at[0] + ux * length, at[1] + uy * length)
    d.polygon([tip, (at[0] - uy * half, at[1] + ux * half), (at[0] + uy * half, at[1] - ux * half)], fill="white")

for name, sign in (("cw", 1), ("ccw", -1)):
    im, d = new()
    R = 70
    if sign > 0:   # PIL arcs run clockwise on screen: from 300 round to 200 degrees
        d.arc([128 - R, 138 - R, 128 + R, 138 + R], start=-60, end=200, fill="white", width=W)
        e = math.radians(200)
        tri(d, (128 + R * math.cos(e), 138 + R * math.sin(e)), e + math.pi / 2)
    else:
        d.arc([128 - R, 138 - R, 128 + R, 138 + R], start=-20, end=240, fill="white", width=W)
        e = math.radians(-20)
        tri(d, (128 + R * math.cos(e), 138 + R * math.sin(e)), e - math.pi / 2)
    save(im, name)

# rebuild: sparkles (work the route out anew)
im, d = new()
def star(cx, cy, r, w):
    d.polygon([(cx, cy - r), (cx + w, cy - w), (cx + r, cy), (cx + w, cy + w),
               (cx, cy + r), (cx - w, cy + w), (cx - r, cy), (cx - w, cy - w)], fill="white")
star(112, 140, 84, 18)
star(196, 66, 40, 9)
save(im, "rebuild")

# delete: X
im, d = new()
line(d, [(72, 72), (184, 184)]); line(d, [(184, 72), (72, 184)])
save(im, "delete")
print("ok")
