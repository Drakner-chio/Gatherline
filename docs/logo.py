# Draws Gatherline's logo: a loop with four nodes and an arrow on a dark
# rounded square. python3 docs/logo.py  ->  media/Logo.tga (64, in the game)
# and media/icon-400.png (the CurseForge project logo). Needs Pillow.
from PIL import Image, ImageDraw
import math

S = 1024
k = S / 512
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
d.rounded_rectangle([16 * k, 16 * k, S - 16 * k, S - 16 * k], radius=110 * k, fill=(17, 21, 26, 255),
                    outline=(47, 54, 64, 255), width=int(10 * k))
jade = (63, 208, 160, 255)
ctrl = [(150, 160), (330, 120), (395, 260), (300, 395), (140, 350)]
ctrl = [(x * k, y * k) for x, y in ctrl]


def cr(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return tuple(0.5 * ((2 * p1[i]) + (-p0[i] + p2[i]) * t + (2 * p0[i] - 5 * p1[i] + 4 * p2[i] - p3[i]) * t2
                        + (-p0[i] + 3 * p1[i] - 3 * p2[i] + p3[i]) * t3) for i in range(2))


n = len(ctrl)
curve = []
for i in range(n):
    p0, p1, p2, p3 = ctrl[(i - 1) % n], ctrl[i], ctrl[(i + 1) % n], ctrl[(i + 2) % n]
    for j in range(40):
        curve.append(cr(p0, p1, p2, p3, j / 40))
curve.append(curve[0])
# a smooth stroke: discs stamped close together along the loop
r = 13 * k
for (ax, ay), (bx, by) in zip(curve, curve[1:]):
    steps = max(1, int(math.hypot(bx - ax, by - ay) / 2))
    for t in range(steps):
        x, y = ax + (bx - ax) * t / steps, ay + (by - ay) * t / steps
        d.ellipse([x - r, y - r, x + r, y + r], fill=jade)
i = int(len(curve) * 0.5)
(x1, y1), (x2, y2) = curve[i], curve[i + 3]
a = math.atan2(y2 - y1, x2 - x1)
L, W = 58 * k, 40 * k
tip = (x1 + math.cos(a) * L * 0.7, y1 + math.sin(a) * L * 0.7)
back = (x1 - math.cos(a) * L * 0.5, y1 - math.sin(a) * L * 0.5)
left = (back[0] + math.cos(a + math.pi / 2) * W, back[1] + math.sin(a + math.pi / 2) * W)
right = (back[0] - math.cos(a + math.pi / 2) * W, back[1] - math.sin(a + math.pi / 2) * W)
d.polygon([tip, left, right], fill=jade)
for (x, y) in [ctrl[0], ctrl[1], ctrl[2], ctrl[4]]:
    R = 36 * k
    d.ellipse([x - R, y - R, x + R, y + R], fill=(17, 21, 26, 255), outline=jade, width=int(14 * k))
    R = 13 * k
    d.ellipse([x - R, y - R, x + R, y + R], fill=(235, 240, 244, 255))
img.resize((64, 64), Image.LANCZOS).save("media/Logo.tga")
img.resize((400, 400), Image.LANCZOS).save("media/icon-400.png")
