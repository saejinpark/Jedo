"""Seigaiha: compass waves under a red sun. Few steps, all of them exact.

The waves are one compass setting repeated: arcs pressed through blue carbon
with the stylus. The sun is a disc cut from red carbon and rolled. The sky is
one sheet of 10% tone, cut along the wave tops and round the sun, with a halo
and bands of mist scraped out of it.

  python3 waves.py out.json
"""
import json, math, sys
st = []
def S(i, pts, g="HB"): st.append({"i": i, "g": g, "pts": pts})
def op(o, pts, k=None): st.append({"i": "", "op": o, "k": k, "pts": [list(p) for p in pts]})
def line(a, b, p=0.5):
    d = math.hypot(b[0]-a[0], b[1]-a[1]); n = max(int(d/1.5), 2)
    return [[a[0]+(b[0]-a[0])*t/n, a[1]+(b[1]-a[1])*t/n, p] for t in range(n+1)]

X0, Y0, X1, Y1 = 45.0, 58.0, 165.0, 238.0     # the picture
R = 12.0; SEA = 150.0                          # the compass setting; the first row's centres
SUN = (105.0, 110.0); SR = 24.0
rows = []
y = SEA; k = 0
while y - R < Y1:
    xs = [X0 + (R if k % 2 == 0 else 0) + 2*R*i for i in range(-1, 7)]
    rows.append([(x, y) for x in xs]); y += R/2; k += 1
def hidden(p, k):
    return any(math.hypot(p[0]-c[0], p[1]-c[1]) < R-0.01 for row in rows[k+1:k+4] for c in row)

# 1. The waves: blue carbon under the stylus, four arcs to a wave from one centre.
op("carbon", [(105, 190, 0)], "blue")
for k, row in enumerate(rows):
    for c in row:
        for r, press in ((R, 1.0), (R*0.74, 0.7), (R*0.48, 0.7), (R*0.22, 0.7)):
            run = []
            for a in range(180, 361):
                t = math.radians(a); p = (c[0]+r*math.cos(t), c[1]+r*math.sin(t))
                ok = X0 <= p[0] <= X1 and p[1] <= Y1 and not hidden(p, k)
                if ok: run.append([p[0], p[1], press])
                if (not ok or a == 360) and run:
                    if len(run) > 3: S("stylus", run)
                    run = []
op("lift", [(105, 190)])

# 2. The sun: a disc cut from red carbon, rolled until it is even.
ring = lambda c, r, n=90: [(c[0]+r*math.cos(2*math.pi*i/n), c[1]+r*math.sin(2*math.pi*i/n)) for i in range(n+1)]
op("carbon", [(105, 130, 0)], "red")
op("slice", ring(SUN, SR))
op("lift", [(105, 200)])
for ys in ((-15, 15), (-30, 0, 30), (-15, 15)):
    for dy in ys: S("roller", line((SUN[0]-SR-5, SUN[1]+dy), (SUN[0]+SR+5, SUN[1]+dy), 0.95))
op("lift", [SUN])

# 3. The sky: one sheet of tone, cut along the wave tops and round the sun.
def top(x):
    return min(c[1]-math.sqrt(R*R-(x-c[0])**2) for row in rows[:2] for c in row if abs(x-c[0]) < R)
op("tone", [(105, 108, 0)], "dots10")
crest = [(X1-i*0.5, top(X1-i*0.5)) for i in range(int((X1-X0)*2)+1)]
op("cut", [(X1+0.5, crest[0][1])] + crest + [(X0-0.5, crest[-1][1])])
op("peel", [(105, 156)])
op("cut", ring(SUN, SR+0.4)); op("peel", [SUN])
for r, passes, p in ((SR+2.6, 4, 1.0), (SR+5.4, 3, 0.85), (SR+8.2, 2, 0.7), (SR+11, 1, 0.55)):
    for _ in range(passes): op("scrape", [(x, y, p) for x, y in ring(SUN, r, 72) if y < top(min(max(x, X0), X1))-1.5])
for y, x0, x1 in ((70, 52, 96), (75, 64, 118), (80, 50, 84), (93, 140, 162), (98, 132, 158)):
    for _ in range(4): op("scrape", [(x0+(x1-x0)*t/24, y, 0.5+0.5*math.sin(math.pi*t/24)) for t in range(25)])

# 4. The frame, in a 0.5 pen.
for a, b in (((X0, Y0), (X1, Y0)), ((X1, Y0), (X1, Y1)), ((X1, Y1), (X0, Y1)), ((X0, Y1), (X0, Y0))): S("p05", line(a, b))

json.dump({"paper": "a4", "landscape": False, "strokes": st}, open(sys.argv[1], "w"))
print(len(st), "steps")
