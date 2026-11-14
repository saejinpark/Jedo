"""A moon jar (달항아리): a white porcelain jar against a tone ground.

Few steps: one circle with the compass, a mouth and a foot with the ruler and
an ellipse template, a crescent of fine compass arcs on the shaded side. Then one sheet of 30%
tone over everything, the jar cut out and lifted so the porcelain is bare
paper, and light scraped out of the tone round its lit side.

  python3 moonjar.py out.json
"""
import json, math, sys
st = []
def S(i, pts, g="HB"): st.append({"i": i, "g": g, "pts": pts})
def op(o, pts, k=None): st.append({"i": "", "op": o, "k": k, "pts": [list(p) for p in pts]})
def line(a, b, p=0.5):
    d = math.hypot(b[0]-a[0], b[1]-a[1]); n = max(int(d/1.2), 2)
    return [[a[0]+(b[0]-a[0])*t/n, a[1]+(b[1]-a[1])*t/n, p] for t in range(n+1)]
def arc(c, rx, ry, a0, a1, step=2.0):
    n = max(int(abs(a1-a0)/step), 2)
    return [(c[0]+rx*math.cos(math.radians(a0+(a1-a0)*t/n)), c[1]+ry*math.sin(math.radians(a0+(a1-a0)*t/n))) for t in range(n+1)]

X0, Y0, X1, Y1 = 55.0, 88.0, 155.0, 208.0      # the picture: one sheet of tone, turned upright
C = (105.0, 150.0); R = 38.0                    # the body: one circle
MOUTH, RIM, RIM_Y = 15.0, 16.5, 110.0           # half the mouth where it leaves the body; the rim
FOOT, FOOT_Y = 13.0, 189.0
ang = lambda half, top: math.degrees(math.atan2(-math.sqrt(R*R-half*half) if top else math.sqrt(R*R-half*half), half))
a_m, a_f = ang(MOUTH, True), ang(FOOT, False)   # where the mouth and the foot meet the circle, on the right

right = arc(C, R, R, a_m, a_f); left = arc(C, R, R, 180-a_f, 180-a_m)
rim_top = arc((C[0], RIM_Y), RIM, 2.0, 180, 360)
outline = rim_top + right + [(C[0]+FOOT, FOOT_Y), (C[0]-FOOT, FOOT_Y)] + left

# 1. The jar in a fine pen: lighter on the lit side, firmer in the shade.
S("maru", [[x, y, 0.3] for x, y in left]); S("maru", [[x, y, 0.55] for x, y in right])
S("maru", [[x, y, 0.4] for x, y in arc((C[0], RIM_Y), RIM, 2.0, 0, 360)])
S("maru", line(left[-1], (C[0]-RIM, RIM_Y), 0.3)); S("maru", line(right[0], (C[0]+RIM, RIM_Y), 0.5))
S("maru", line(left[0], (C[0]-FOOT, FOOT_Y), 0.35)); S("maru", line(right[-1], (C[0]+FOOT, FOOT_Y), 0.55))
S("maru", line((C[0]-FOOT, FOOT_Y), (C[0]+FOOT, FOOT_Y), 0.5))

# 2. Shade with the compass: arcs from the same centre, each a little smaller, kept to a crescent
#    on the side away from the light (outside a second circle struck toward the light).
L = (C[0]-10.0, C[1]-10.0)
r = R-0.8
while r > R-15:
    run = []
    for x, y in arc(C, r, r, -70, 160, 1.0):
        if math.hypot(x-L[0], y-L[1]) > R-0.5: run.append([x, y, 0.18+0.3*(r-(R-15))/15])
    if len(run) > 3: S("m03", run, "H")
    r -= 0.75
# the dark inside the mouth
for k in range(7):
    y = RIM_Y-1.3+k*0.42; w = RIM*math.sqrt(max(1-((y-RIM_Y)/2.0)**2, 0))*0.92
    S("maru", line((C[0]-w, y), (C[0]+w, y), 0.6))

# 3. Its shadow on the ground, hatched level.
for k in range(9):
    y = FOOT_Y+0.5+k*0.6; w = 30*math.sqrt(max(1-((y-FOOT_Y)/5.6)**2, 0))
    S("p013", line((C[0]+6-w, y), (C[0]+6+w, y)))

# 4. Tone over the lot; the jar cut out and lifted.
op("tone", [((X0+X1)/2, (Y0+Y1)/2, math.pi/2)], "dots30")
op("cut", outline+outline[:1])
op("peel", [C])

# 5. Light scraped out of the ground on the lit side: firm near the jar, fading away from it.
d = 1.8
while d < 20:
    fade = 1-d/20
    ring = [(x, y) for x, y in arc(C, R+d, R+d, 140, 300, 2.5)]
    n = len(ring)-1
    for _ in range(1+int(4*fade)):
        op("scrape", [(x, y, (0.35+0.65*fade)*max(math.sin(math.pi*k/n), 0)**0.6) for k, (x, y) in enumerate(ring) if X0+1 < x < X1-1 and Y0+1 < y])
    d += 1.4

# 6. The frame.
for a, b in (((X0, Y0), (X1, Y0)), ((X1, Y0), (X1, Y1)), ((X1, Y1), (X0, Y1)), ((X0, Y1), (X0, Y0))): S("p05", line(a, b))

json.dump({"paper": "a4", "landscape": False, "strokes": st}, open(sys.argv[1], "w"))
print(len(st), "steps")
