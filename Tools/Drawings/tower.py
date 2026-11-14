"""A manga panel: a keep on a rock under a clouded moon, in two-point perspective.

Shows the other hand at work as well as the pen: two pins at the vanishing
points with the ruler swung against them, G-pen outlines, maru-pen stone
courses and hatching, then screen tone laid, cut with the knife, peeled, and
scraped with the blade laid flat. Runs with the debug script runner.

  python3 tower.py out.json
"""
import json, math, random, sys
random.seed(7)
st = []
def S(i, pts, g="HB"): st.append({"i": i, "g": g, "pts": pts})
def op(o, pts, k=None): st.append({"i": "", "op": o, "k": k, "pts": pts})
def line(a, b, p=0.5, taper=False):
    d = math.hypot(b[0]-a[0], b[1]-a[1]); n = max(int(d/1.5), 2)
    return [[a[0]+(b[0]-a[0])*t/n, a[1]+(b[1]-a[1])*t/n, p*(0.55+0.45*math.sin(math.pi*t/n)) if taper else p] for t in range(n+1)]

L, R = (18.0, 172.0), (279.0, 172.0)      # the pins
CX, XL, XR = 150.0, 108.0, 188.0          # the near corner, and where each face ends
MER, TOP, BASE = 40.0, 48.0, 148.0        # heights at the corner
def lf(yc, x): return L[1]+(yc-L[1])*(x-L[0])/(CX-L[0])
def rf(yc, x): return R[1]+(yc-R[1])*(R[0]-x)/(R[0]-CX)

# The ruler, laid with its graduated edge on the line; against a pin when the line runs to one.
last_pose = [None]
def lay_ruler(a, b, pin=None):
    ends = [a, b] + ([pin] if pin else [])
    th = math.atan2(b[1]-a[1], b[0]-a[0])
    if th > math.pi/2 or th <= -math.pi/2: th += math.pi if th < 0 else -math.pi
    u = (math.cos(th), math.sin(th)); ts = [e[0]*u[0]+e[1]*u[1] for e in ends]
    lo, hi = min(ts), max(ts); seg = sorted(ts[:2])
    mid = (lo+hi)/2
    if hi-lo > 200: mid = min(max(mid, seg[1]-100), seg[0]+100)
    off = a[0]*-u[1]+a[1]*u[0]
    c = (u[0]*mid - u[1]*(off+15), u[1]*mid + u[0]*(off+15))
    pose = [round(c[0], 2), round(c[1], 2), round(th, 4)]
    if pose != last_pose[0]: op("tool", [pose], "ruler"); last_pose[0] = pose
def ruled(a, b, i, g="HB", p=0.5, pin=None, taper=False):
    lay_ruler(a, b, pin); S(i, line(a, b, p, taper), g)
pencil = lambda a, b, pin=None: ruled(a, b, "m03", "4H", 0.28, pin)
gpen = lambda a, b, pin=None: ruled(a, b, "g", "HB", 0.62, pin, True)
maru = lambda a, b, pin=None: ruled(a, b, "maru", "HB", 0.4, pin)

# 1. Pins, the panel frame, then construction in a hard pencil.
op("pins", [list(L), list(R)])
F = (25.0, 15.0, 272.0, 195.0)
for a, b in (((F[0], F[1]), (148, F[1])), ((148, F[1]), (F[2], F[1])), ((F[2], F[1]), (F[2], F[3])),
             ((F[2], F[3]), (148, F[3])), ((148, F[3]), (F[0], F[3])), ((F[0], F[3]), (F[0], F[1]))):
    ruled(a, b, "p07")
pencil((45, L[1]), (250, L[1]))
pencil((CX, 34), (CX, 158))
for yc in (MER, TOP, BASE):
    pencil((CX, yc), (XL-6, lf(yc, XL-6)), L); pencil((CX, yc), (XR+6, rf(yc, XR+6)), R)
pencil((XL, lf(MER, XL)-4), (XL, lf(BASE, XL)+4)); pencil((XR, rf(MER, XR)-4), (XR, rf(BASE, XR)+4))

# 2. Outlines in the G pen, every receding edge off its pin.
xl = [150, 143, 136.5, 130.5, 125, 120, 115.5, 111.5, 108]
xr = [150, 157, 163.5, 169.5, 175, 180, 184.5, 188]
def battlement(xs, f, pin):
    for k, (x0, x1) in enumerate(zip(xs, xs[1:])):
        if k % 2 == 0: gpen((x0, f(MER, x0)), (x1, f(MER, x1)), pin)
    for k, (x0, x1) in enumerate(zip(xs, xs[1:])):
        if k % 2 == 1: gpen((x0, f(TOP, x0)), (x1, f(TOP, x1)), pin)
    for x in xs[1:-1] + ([] if len(xs) % 2 == 0 else []): gpen((x, f(MER, x)), (x, f(TOP, x)))
def silhouette(xs, f):
    pts = []
    for k, (x0, x1) in enumerate(zip(xs, xs[1:])):
        y = MER if k % 2 == 0 else TOP
        pts += [(x0, f(y, x0)), (x1, f(y, x1))]
    return pts
battlement(xl, lf, L); battlement(xr, rf, R)
gpen((CX, MER), (CX, BASE))
gpen((XL, silhouette(xl, lf)[-1][1]), (XL, lf(BASE, XL))); gpen((XR, silhouette(xr, rf)[-1][1]), (XR, rf(BASE, XR)))
gpen((CX, BASE), (XL, lf(BASE, XL)), L); gpen((CX, BASE), (XR, rf(BASE, XR)), R)

# 3. The gate and the arrow slits.
GX0, GX1, GS = 161.0, 177.0, 118.0
arch = [(GX0+(GX1-GX0)*(1-math.cos(t))/2, rf(GS, GX0+(GX1-GX0)*(1-math.cos(t))/2)-9*math.sin(t)) for t in [math.pi*k/16 for k in range(17)]]
gate = [(GX0, rf(BASE, GX0))] + arch + [(GX1, rf(BASE, GX1))]
gpen(gate[0], arch[0]); gpen(gate[-1], arch[-1])
S("g", [[x, y, 0.6] for x, y in arch])
slits = [("l", 126.5, 129.5, 74, 93), ("r", 167.0, 169.5, 64, 82)]
def slit_poly(side, x0, x1, y0, y1):
    f = lf if side == "l" else rf
    return [(x0, f(y0, x0)), (x1, f(y0, x1)), (x1, f(y1, x1)), (x0, f(y1, x0))]

# 4. Stone courses off the pins in the maru pen, broken where the gate and slits are.
courses = list(range(57, 148, 9))
for yc in courses:
    cut = [s for s in slits if s[0] == "l" and s[3] < yc < s[4]]
    xs = [CX] + [v for s in cut for v in (s[2], s[1])] + [XL]
    for x0, x1 in zip(xs[0::2], xs[1::2]): maru((x0, lf(yc, x0)), (x1, lf(yc, x1)), L)
for yc in courses:
    xs = [CX] + ([GX0, GX1] if yc > 110 else []) + [v for s in slits if s[0] == "r" and s[3] < yc < s[4] for v in (s[1], s[2])] + [XR]
    for x0, x1 in zip(xs[0::2], xs[1::2]): maru((x0, rf(yc, x0)), (x1, rf(yc, x1)), R)
op("untool", [], "ruler")

# 5. Freehand: the joints between stones, the dark of the openings, the rock, the moon, birds.
def inside(p, poly):
    c = False
    for a, b in zip(poly, poly[1:]+poly[:1]):
        if (a[1] > p[1]) != (b[1] > p[1]) and p[0] < a[0]+(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1]): c = not c
    return c
holes = [gate] + [slit_poly(*s) for s in slits]
bands = [TOP] + courses + [BASE]
for k, (y0, y1) in enumerate(zip(bands, bands[1:])):
    for f, sign, end in ((lf, -1, XL), (rf, 1, XR)):
        x = CX + sign*(3.5 if k % 2 else 7); step = 7.5
        while (x-end)*sign < -1:
            j = random.uniform(-0.25, 0.25)
            a, b = (x+j, f(y0, x)+0.3), (x-j, f(y1, x)-0.3)
            if not any(inside(((a[0]+b[0])/2, (a[1]+b[1])/2), h) for h in holes): S("maru", line(a, b, 0.32))
            x += sign*step; step *= 0.93
def hatch(poly, gap, i, p, both=True):
    for sgn in ((1, -1) if both else (1,)):
        f = lambda q: q[0]+sgn*q[1]
        lo, hi = min(map(f, poly)), max(map(f, poly)); c = lo+gap/2
        while c < hi:
            xs = []
            for a, b in zip(poly, poly[1:]+poly[:1]):
                fa, fb = f(a)-c, f(b)-c
                if (fa < 0) != (fb < 0): xs.append(a[0]+(b[0]-a[0])*fa/(fa-fb))
            xs.sort()
            for x0, x1 in zip(xs[0::2], xs[1::2]):
                if x1-x0 > 0.2: S(i, line((x0, sgn*(c-x0)), (x1, sgn*(c-x1)), p))
            c += gap
hatch(gate, 0.9, "maru", 0.7)
for s in slits:
    poly = slit_poly(*s); S("g", line(poly[0], poly[3], 0.5)); S("g", line(poly[1], poly[2], 0.5)); hatch(poly, 0.7, "maru", 0.7)
# the rock: a broken outline, then clumps of short strokes following its fall
def jag(pts, amp):
    out = []
    for a, b in zip(pts, pts[1:]):
        n = max(int(math.hypot(b[0]-a[0], b[1]-a[1])/3), 1)
        out += [(a[0]+(b[0]-a[0])*t/n+random.uniform(-amp, amp), a[1]+(b[1]-a[1])*t/n+random.uniform(-amp, amp)) for t in range(n)]
    return out+[pts[-1]]
left = jag([(26, 181), (52, 172), (70, 174), (88, 162), (100, 163), (XL, lf(BASE, XL))], 0.9)
right = jag([(XR, rf(BASE, XR)), (201, 160), (214, 168), (236, 166), (254, 177), (271, 180)], 0.9)
for run in (left, right): S("g", [[x, y, random.uniform(0.45, 0.85)] for x, y in run])
ground = left + [(CX, BASE)] + right
def ground_y(x):
    for a, b in zip(ground, ground[1:]):
        if a[0] <= x <= b[0] and b[0] > a[0]: return a[1]+(b[1]-a[1])*(x-a[0])/(b[0]-a[0])
    return 180
for _ in range(46):
    x = random.uniform(30, 266); y = ground_y(x)+random.uniform(2, min(24, 192-ground_y(x)-3)); lean = random.choice((0.5, 0.5, -0.35))
    for k in range(random.randint(4, 8)):
        l = random.uniform(3.5, 7); a = (x+k*0.95, y+k*0.2*lean)
        b = (a[0]+l*lean, min(a[1]+l, 193.5))
        S("maru", line(a, b, random.uniform(0.35, 0.6)))
M, MR = (80.0, 62.0), 22.0
circle = [(M[0]+MR*math.cos(TA), M[1]+MR*math.sin(TA)) for TA in [2*math.pi*k/90 for k in range(91)]]
S("maru", [[x, y, 0.45] for x, y in circle])
for bx, by, w in ((206, 52, 4.0), (216, 46, 3.2), (224, 58, 3.6), (236, 41, 2.6), (198, 66, 2.8)):
    S("g", [[bx-w, by-w*0.45, 0.3], [bx-w*0.4, by-w*0.5, 0.6], [bx, by, 0.7], [bx+w*0.45, by-w*0.6, 0.6], [bx+w, by-w*0.35, 0.3]])

# 6. Tone on the shadowed face: lay a sheet, cut round the face, peel the waste.
sil_r = silhouette(xr, rf)
face = sil_r + [(XR, rf(BASE, XR)), (CX, BASE)]
op("tone", [[169, 96, math.pi/2]], "dots30")
op("cut", [list(p) for p in face + face[:1]])
op("peel", [[123, 100]])

# 7. Tone for the cloud: cut a ragged shape, lift the rest, free the keep and the moon, scrape light into it.
cloud = [(92+55*math.cos(t)*(1+0.08*math.sin(5*t)), 68+30*math.sin(t)*(1+0.12*math.sin(7*t))) for t in [2*math.pi*k/160 for k in range(161)]]
op("tone", [[92, 70, 0]], "dots10")
op("cut", [list(p) for p in cloud])
op("peel", [[34, 22.5]])
sil_l = silhouette(xl, lf)
op("cut", [[XL, 116]] + [list(p) for p in reversed(sil_l)] + [list(p) for p in sil_r[:2]] + [[sil_r[1][0], 116]])
op("peel", [[130, 80]])
op("cut", [list(p) for p in circle])
op("peel", [list(M)])
for y0, y1, x0, x1 in ((90, 86, 44, 104), (84, 81, 40, 60), (95, 92, 62, 106), (50, 47, 104, 132)):
    for _ in range(3): op("scrape", [[x0+(x1-x0)*t/20, y0+(y1-y0)*t/20+0.8*math.sin(t*0.9), 0.9] for t in range(21)])

json.dump({"paper": "a4", "landscape": True, "strokes": st}, open(sys.argv[1], "w"))
print(len(st), "steps")
