"""Five skirts, each a different cloth: carbon coated with a fabric print, cut to the
skirt's shape and pressed with the roller, then outlined in pen.

  python3 cloth.py out.json
"""
import json, math, sys
st = []
def S(i, pts, g="HB"): st.append({"i": i, "g": g, "pts": pts})
def op(o, pts, k=None): st.append({"i": "", "op": o, "k": k, "pts": [list(p) for p in pts]})
def line(a, b, p=0.5):
    d = math.hypot(b[0]-a[0], b[1]-a[1]); n = max(int(d/1.5), 2)
    return [[a[0]+(b[0]-a[0])*t/n, a[1]+(b[1]-a[1])*t/n, p] for t in range(n+1)]

TOP, LEN, WAIST, HEM = 78.0, 54.0, 9.0, 21.0
for k, ink in enumerate(("stripe", "gingham", "dots", "tartan", "houndstooth")):
    cx = 40.0 + 54*k
    # an A-line skirt: side seams flaring out, the hem a shallow curve
    hem = [(cx+HEM*math.cos(math.pi*t/20), TOP+LEN+3*math.sin(math.pi*t/20)) for t in range(21)]
    skirt = [(cx-WAIST, TOP), (cx+WAIST, TOP)] + hem
    op("carbon", [(cx, 105, 0)], ink)
    op("slice", skirt+skirt[:1])
    op("lift", [(cx, 180)])
    for _ in range(2):
        for y in (TOP+13, TOP+43): S("roller", line((cx-HEM-4, y), (cx+HEM+4, y), 0.95))
    op("lift", [(cx, TOP+25)])
    for a, b in zip(skirt, skirt[1:]+skirt[:1]): S("maru", line(a, b, 0.5))
    # the waistband
    for a, b in (((cx-WAIST, TOP), (cx-WAIST, TOP-4)), ((cx-WAIST, TOP-4), (cx+WAIST, TOP-4)), ((cx+WAIST, TOP-4), (cx+WAIST, TOP))): S("maru", line(a, b, 0.5))

json.dump({"paper": "a4", "landscape": True, "strokes": st}, open(sys.argv[1], "w"))
print(len(st), "steps")
