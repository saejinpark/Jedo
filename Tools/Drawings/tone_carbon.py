"""Three panels on what tone, carbon and collage are for.

1. Night sea: one sheet of 50% tone; the moon cut out sharp, its halo, the
   clouds and the light on the water scraped out soft with the blade laid flat.
2. Colour like a print: navy carbon and the stylus for line, a disc cut from
   red carbon and a band cut from a gradient carbon pressed with the roller.
3. Collage: pieces cut from two prints and glued, a print used as carbon and
   rolled through, line tone over the lot.

Needs manga.jpg and plan.jpg (any two pictures) beside the script in Documents.

  python3 tone_carbon.py out.json
"""
import json, math, random, sys
random.seed(11)
st = []
def S(i, pts, g="HB"): st.append({"i": i, "g": g, "pts": pts})
def op(o, pts, k=None): st.append({"i": "", "op": o, "k": k, "pts": [list(p) for p in pts]})
def line(a, b, p=0.5):
    d = math.hypot(b[0]-a[0], b[1]-a[1]); n = max(int(d/1.5), 2)
    return [[a[0]+(b[0]-a[0])*t/n, a[1]+(b[1]-a[1])*t/n, p] for t in range(n+1)]
def frame(x0, y0, x1, y1):
    for a, b in (((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0))): S("p07", line(a, b))
def ring(c, rx, ry, n=72, wob=0.0, k=5):
    return [(c[0]+rx*math.cos(t)*(1+wob*math.sin(k*t)), c[1]+ry*math.sin(t)*(1+wob*math.sin((k+2)*t))) for t in [2*math.pi*i/n for i in range(n+1)]]
TAU = 2*math.pi

# ---------- 1. Night sea: tone cut and scraped ----------
A = (14.0, 14.0, 110.0, 130.0); HZ = 92.0; M = (78.0, 42.0); MR = 11.0
frame(*A)
S("maru", line((A[0], HZ), (A[2], HZ), 0.4))
# a rock in the water, inked solid with crossed strokes
rock = [(22, 104), (27, 93), (33, 88), (38, 95), (44, 91), (50, 104)]
S("g", [[x, y, 0.7] for x, y in rock])
for k in range(34):
    x = 22.5+k*0.8; top = min(104, max(88, 104-abs(14-abs(x-36))*0.0-(16-abs(x-36)*1.1)))
    S("maru", line((x, 104), (x+1.5, max(top, 88.5)), 0.7))
op("tone", [(62, 72, math.pi/2)], "dots50")
op("cut", [(A[0], A[1]), (A[2], A[1]), (A[2], A[3]), (A[0], A[3]), (A[0], A[1])])
op("peel", [(12.8, 12.8)])
moon = ring(M, MR, MR)
op("cut", moon); op("peel", [M])
S("maru", [[x, y, 0.4] for x, y in moon])
# the halo: rings scraped round the moon, fewer passes farther out
for r, passes, p in ((13.2, 5, 1.0), (16.0, 4, 0.9), (18.8, 3, 0.8), (21.6, 2, 0.6), (24.4, 1, 0.5)):
    for k in range(passes): op("scrape", [(x, y, p) for x, y in ring(M, r, r, 60)])
# clouds: long soft sweeps
for y, x0, x1, passes in ((26, 18, 70, 2), (29, 30, 92, 3), (62, 16, 58, 2), (66, 40, 106, 2)):
    for k in range(passes):
        op("scrape", [(x0+(x1-x0)*t/30, y+1.6*math.sin(t*0.5+k), 0.75) for t in range(31)])
# moonlight on the water: short strokes, wider and fainter toward the bottom
y = HZ+2.2
while y < A[3]-2:
    w = 4+(y-HZ)*0.42
    for k in range(3 if y < HZ+16 else 2):
        op("scrape", [(M[0]-w+2*w*t/12+random.uniform(-0.6, 0.6), y+0.25*math.sin(t*1.3), 0.95) for t in range(13)])
    for side in (-1, 1):
        if random.random() < 0.55:
            c = M[0]+side*(w+random.uniform(3, 9)); l = random.uniform(2, 5)
            op("scrape", [(c-l, y, 0.7), (c+l, y+0.2, 0.7)])
    y += 3.6

# ---------- 2. Colour like a print: carbon, stylus, roller ----------
B = (118.0, 14.0, 283.0, 100.0)
op("carbon", [(200, 57, math.pi/2)], "navy")
peak = [(124, 99), (150, 92), (176, 70), (198, 46), (206, 37), (211, 39), (216, 36), (222, 40), (236, 58), (258, 80), (282, 94)]
S("stylus", [[x, y, 0.85] for a, b in zip(peak, peak[1:]) for x, y, _ in line(a, b)])
snow = [(194, 51), (199, 55), (203, 49), (208, 57), (213, 50), (218, 58), (223, 51), (228, 56), (231, 52)]
S("stylus", [[x, y, 0.7] for x, y in snow])
for k in range(9):
    x = 186+k*6.5; S("stylus", line((x, 66+abs(k-4)*1.5), (x-9, 84+abs(k-4)*1.5), 0.55))
op("lift", [(200, 57)])
SUN = (152.0, 44.0); SR = 16.0
op("carbon", [(160, 60, math.pi/2)], "red")
op("slice", ring(SUN, SR, SR, 60))
op("lift", [(230, 60)])
for yy in (SUN[1]-15, SUN[1]+15): S("roller", line((SUN[0]-SR-6, yy), (SUN[0]+SR+6, yy), 0.9))
op("lift", [SUN])
op("carbon", [(200, 70, math.pi/2)], "sea")
wave = [(121+k*2, 84+2.6*math.sin(k*0.42)+1.2*math.sin(k*1.1)) for k in range(81)] + [(281, 98), (121, 98)]
op("slice", wave+wave[:1])
op("lift", [(200, 40)])
S("roller", line((117, 90), (285, 90), 0.9))
op("lift", [(200, 94)])
frame(*B)

# ---------- 3. Collage: prints cut and glued, a print as carbon, tone over ----------
C = (118.0, 106.0, 283.0, 196.0)
op("photo", [(163, 151, 0)], "manga.jpg")
blob = ring((160, 150), 33, 37, 40, 0.07, 3)
op("slice", blob); op("lift", [(95, 151)]); op("glue", [(160, 150)])
op("photo", [(190, 152, 0.3)], "plan.jpg")
tri = [(178, 120), (206, 138), (184, 186)]
op("slice", tri+tri[:1]); op("lift", [(190, 100)]); op("glue", [(189.3, 148)])
op("photocarbon", [(245, 151, 0)], "manga.jpg")
S("roller", line((213, 125), (266, 131), 0.9)); S("roller", line((216, 170), (266, 162), 0.9))
op("lift", [(250, 151)])
# shadows hatched under the glued pieces, to seat them on the page
for poly_edge in ((tri[1], tri[2]), (blob[2], blob[8])):
    a, b = poly_edge
    for k in range(int(math.hypot(b[0]-a[0], b[1]-a[1])/1.1)):
        t = k*1.1/math.hypot(b[0]-a[0], b[1]-a[1]); x = a[0]+(b[0]-a[0])*t; y = a[1]+(b[1]-a[1])*t
        S("maru", line((x+0.6, y+0.4), (x+3.6+random.uniform(0, 1.2), y+2.6), 0.45))
op("tone", [(200, 172, 0)], "lines")
band = [(143+k*2, 181+1.8*math.sin(k*0.5)) for k in range(58)] + [(257, 194), (143, 194)]
op("cut", band+band[:1]); op("peel", [(142, 124)])
frame(*C)

json.dump({"paper": "a4", "landscape": True, "strokes": st}, open(sys.argv[1], "w"))
print(len(st), "steps")
