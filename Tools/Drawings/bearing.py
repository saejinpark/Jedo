"""A flanged bearing housing: front view and section A-A, 1:1 on A4 landscape.

A drawing that needs the whole desk: hard-pencil construction and projection
lines (parallel rule), circles (compass, circle template), outlines in a 0.5
pen, chain centre lines and 45-degree section hatching in fine pens (set
square on the parallel rule), dimensions and lettering.

  python3 bearing.py out.json
"""
import json, math, sys

st = []
def S(i, pts, g="HB"): st.append({"i": i, "g": g, "pts": pts})
def line(a, b, p=0.5):
    d = math.hypot(b[0]-a[0], b[1]-a[1]); n = max(int(d/2), 1)
    return [[a[0]+(b[0]-a[0])*t/n, a[1]+(b[1]-a[1])*t/n, p] for t in range(n+1)]
def arc(c, r, a0, a1, p=0.5):
    n = max(int(abs(a1-a0)*r/1.2), 8)
    return [[c[0]+r*math.cos(a0+(a1-a0)*t/n), c[1]+r*math.sin(a0+(a1-a0)*t/n), p] for t in range(n+1)]
TAU = 2*math.pi

C = (85.0, 95.0)            # centre of the front view
X0, XF, XC, X1 = 175.0, 189.0, 223.0, 235.0   # section: face, flange, counterbore step, end
R_FL, R_HUB, R_CB, R_BORE, R_PCD, R_HOLE = 50.0, 28.0, 20.0, 15.0, 39.0, 4.5
cy = C[1]

# 1. Construction, 4H and light: centre cross, projection lines, section limits.
con = lambda a, b: S("m03", line(a, b, 0.28), "4H")
con((25, cy), (262, cy)); con((C[0], 28), (C[0], 162))
for r in (R_FL, R_HUB, R_CB, R_BORE):
    for s in (-1, 1): con((C[0], cy+s*r), (X1+6, cy+s*r))
for x in (X0, XF, XC, X1): con((x, 38), (x, 152))

# 2. Chain centre lines, 0.18 pen.
def chain(a, b):
    d = math.hypot(b[0]-a[0], b[1]-a[1]); u = ((b[0]-a[0])/d, (b[1]-a[1])/d); t = 0
    at = lambda s: (a[0]+u[0]*s, a[1]+u[1]*s)
    while t < d:
        e = min(t+10, d); S("p018", line(at(t), at(e))); t = e+1.5
        if t+1.2 < d: S("p018", line(at(t), at(t+1.2)))
        t += 2.7
def chain_arc(c, r):
    step = 10/r; gap = 1.5/r; dot = 1.2/r; n = round(TAU/(step+2*gap+dot)); k = TAU/n/(step+2*gap+dot); a = 0
    for _ in range(n):
        S("p018", arc(c, r, a, a+step*k)); S("p018", arc(c, r, a+(step+gap)*k, a+(step+gap+dot)*k)); a += TAU/n
chain((27, cy), (143, cy)); chain((C[0], 37), (C[0], 153)); chain((X0-5, cy), (X1+5, cy))
chain_arc(C, R_PCD)
holes = [(C[0]+R_PCD*math.cos(math.radians(90+60*k)), cy+R_PCD*math.sin(math.radians(90+60*k))) for k in range(6)]
for s in (-1, 1): S("p018", line((X0-4, cy+s*R_PCD), (XF+4, cy+s*R_PCD)))

# 3. Front view outlines, 0.5 pen: flange, hub, counterbore, bore, six holes.
for r in (R_FL, R_HUB, R_CB, R_BORE): S("p05", arc(C, r, 0, TAU))
for h in holes: S("p05", arc(h, R_HOLE, 0, TAU))

# 4. Section outlines.
out = lambda *pts: [S("p05", line(a, b)) for a, b in zip(pts, pts[1:])]
out((X0, cy-R_FL), (XF, cy-R_FL), (XF, cy-R_HUB), (X1, cy-R_HUB), (X1, cy+R_HUB), (XF, cy+R_HUB), (XF, cy+R_FL), (X0, cy+R_FL), (X0, cy-R_FL))
for s in (-1, 1):
    out((X0, cy+s*R_BORE), (XC, cy+s*R_BORE), (XC, cy+s*R_CB), (X1, cy+s*R_CB))
    for e in (-1, 1): out((X0, cy+s*R_PCD+e*R_HOLE), (XF, cy+s*R_PCD+e*R_HOLE))
out((XC, cy-R_BORE), (XC, cy+R_BORE))

# 5. Hatching at 45 degrees, 2.5 mm apart, 0.13 pen: only where metal is cut.
def hatch(polys, gap=2.5):
    edges = [(p[k], p[(k+1) % len(p)]) for p in polys for k in range(len(p))]
    lo = min(a[0]+a[1] for a, _ in edges); hi = max(a[0]+a[1] for a, _ in edges)
    c = lo + gap
    while c < hi:
        xs = []
        for a, b in edges:
            fa, fb = a[0]+a[1]-c, b[0]+b[1]-c
            if (fa < 0) != (fb < 0): t = fa/(fa-fb); xs.append(a[0]+(b[0]-a[0])*t)
        xs.sort()
        for x0, x1 in zip(xs[0::2], xs[1::2]):
            if x1-x0 > 0.3: S("p013", line((x0, c-x0), (x1, c-x1)))
        c += gap*math.sqrt(2)
for s in (-1, 1):
    Y = lambda r: cy+s*r
    hatch([[(X0, Y(R_FL)), (XF, Y(R_FL)), (XF, Y(R_HUB)), (X1, Y(R_HUB)), (X1, Y(R_CB)), (XC, Y(R_CB)), (XC, Y(R_BORE)), (X0, Y(R_BORE))],
           [(X0, Y(R_PCD-R_HOLE)), (XF, Y(R_PCD-R_HOLE)), (XF, Y(R_PCD+R_HOLE)), (X0, Y(R_PCD+R_HOLE))]])

# 6. Lettering: single-stroke figures on a 4 by 6 grid.
O = [(1,0),(3,0),(4,1),(4,5),(3,6),(1,6),(0,5),(0,1),(1,0)]
GLYPH = {
 "0": [O], "1": [[(1,1),(2,0),(2,6)]], "2": [[(0,1),(1,0),(3,0),(4,1),(4,2),(0,6),(4,6)]],
 "3": [[(0,0),(4,0),(2,2.5),(3,2.5),(4,3.5),(4,5),(3,6),(1,6),(0,5)]], "4": [[(3,6),(3,0),(0,4),(4,4)]],
 "5": [[(4,0),(0,0),(0,2.5),(3,2.5),(4,3.5),(4,5),(3,6),(1,6),(0,5)]],
 "6": [[(4,0.5),(3,0),(1,0),(0,1),(0,5),(1,6),(3,6),(4,5),(4,3.5),(3,2.5),(0,2.5)]], "7": [[(0,0),(4,0),(1.5,6)]],
 "8": [[(1,0),(3,0),(4,1),(4,2),(3,3),(1,3),(0,2),(0,1),(1,0)], [(1,3),(0,4),(0,5),(1,6),(3,6),(4,5),(4,4),(3,3)]],
 "9": [[(4,2.5),(1,2.5),(0,1.5),(0,1),(1,0),(3,0),(4,1),(4,5),(3,6),(1,6),(0,5.5)]],
 "Ø": [O, [(0,6.6),(4,-0.6)]], "A": [[(0,6),(2,0),(4,6)], [(0.8,4),(3.2,4)]], "-": [[(0.5,3),(3.5,3)]],
 ":": [[(2,1.6),(2,2.1)], [(2,4.4),(2,4.9)]],
}
def width(s, h): return (len(s)*5.5-1.5)*h/6
def text(s, x, y, h=3.5, up=False):
    k = h/6
    for n, ch in enumerate(s):
        for path in GLYPH[ch]:
            pts = []
            for a, b in zip(path, path[1:]):
                seg = [((n*5.5+u)*k, v*k) for u, v in (a, b)]
                seg = [(x+v, y-u) if up else (x+u, y+v) for u, v in seg]
                pts += line(seg[0], seg[1], 0.5)[(1 if pts else 0):]
            S("p025", pts)

# 7. Dimensions, 0.18 pen: extension lines, dimension line, arrowheads, figure.
def arrow(tip, toward):
    a = math.atan2(toward[1]-tip[1], toward[0]-tip[0])
    for d in (-0.22, 0.22): S("p018", line(tip, (tip[0]+3*math.cos(a+d), tip[1]+3*math.sin(a+d))))
def dim_h(x0, x1, y, frm, label):
    for x in (x0, x1): S("p018", line((x, frm), (x, y+2)))
    S("p018", line((x0, y), (x1, y))); arrow((x0, y), (x1, y)); arrow((x1, y), (x0, y))
    text(label, (x0+x1)/2-width(label, 3.5)/2, y-1.2-3.5)
def dim_v(y0, y1, x, frm, label):
    for y in (y0, y1): S("p018", line((frm, y), (x+(2 if x > frm else -2), y)))
    S("p018", line((x, y0), (x, y1))); arrow((x, y0), (x, y1)); arrow((x, y1), (x, y0))
    text(label, x-1.2-3.5, (y0+y1)/2+width(label, 3.5)/2, up=True)
dim_h(X0, XF, 157, 147, "14"); dim_h(X0, X1, 167, 147, "60")
dim_v(cy-R_BORE, cy+R_BORE, 244, X1+2, "Ø30"); dim_v(cy-R_HUB, cy+R_HUB, 254, X1+2, "Ø56")
dim_v(cy-R_FL, cy+R_FL, 164, X0-2, "Ø100")
h = holes[4]; e = (h[0]+R_HOLE*math.cos(-math.pi/4), h[1]+R_HOLE*math.sin(-math.pi/4)); k = (h[0]+22, h[1]-22)
S("p018", line(e, k)); S("p018", line(k, (k[0]+width("6-Ø9", 3.5)+2, k[1]))); arrow(e, k); text("6-Ø9", k[0]+1, k[1]-1.2-3.5)

# 8. Cutting plane A-A and the view's name.
for y0, y1, ty in ((27, 36, 26), (154, 163, 160.5)):
    S("p07", line((C[0], y0), (C[0], y1)))
    ya = y0+1.5 if y0 < cy else y1-1.5
    S("p018", line((C[0]+10, ya), (C[0], ya))); arrow((C[0], ya), (C[0]+10, ya)); text("A", C[0]+12, ty, 4.5)
text("A-A", (X0+X1)/2-width("A-A", 4.5)/2, 26, 4.5)

# 9. Border and title block, 0.7 pen.
box = lambda x0, y0, x1, y1, i: [S(i, line(a, b)) for a, b in (((x0,y0),(x1,y0)), ((x1,y0),(x1,y1)), ((x1,y1),(x0,y1)), ((x0,y1),(x0,y0)))]
box(10, 10, 287, 200, "p07"); S("p07", line((207, 180), (287, 180))); S("p07", line((207, 180), (207, 200)))
S("p025", line((207, 190), (287, 190))); S("p025", line((255, 180), (255, 200)))
text("1:1", 262, 183.2, 3.5); text("A4", 263, 193.2, 3.5)

json.dump({"paper": "a4", "landscape": True, "strokes": st}, open(sys.argv[1], "w"))
print(len(st), "strokes")
