#!/usr/bin/env python3
"""Summarise Jedo's stroke log: how far each stroke's line was pulled off the pencil.

Usage: summary.py strokes.jsonl [last N]
"""
import json, math, sys

path = sys.argv[1]
last = int(sys.argv[2]) if len(sys.argv) > 2 else 40
rows = [json.loads(l) for l in open(path) if l.strip()]

def pull(r):
    d = [math.dist(p, q) for p, q in zip(r["pencil"], r["line"])]
    if not d:
        return 0, 0, 0
    return max(d), sum(d) / len(d), sum(1 for x in d if x > 0.2) / len(d)

def length(r):
    p = r["pencil"]
    return sum(math.dist(a, b) for a, b in zip(p, p[1:]))

print(f"{len(rows)} strokes, showing the last {min(last, len(rows))}")
print(f"{'#':>3} {'guide':6} {'grade':5} {'mm':>6} {'s':>5} {'pull max':>8} {'mean':>6} {'moved':>6} {'blunt':>9}  tools")
for i, r in enumerate(rows[-last:], start=max(len(rows) - last, 0) + 1):
    mx, mean, share = pull(r)
    flag = "  <- pulled" if mx > 1.0 else ""
    b = r.get("bluntness") or []
    blunt = f"{b[0]:.2f}>{b[-1]:.2f}" if b else "-"
    print(f"{i:>3} {r['guide']:6} {r['grade']:5} {length(r):6.1f} {r['seconds']:5.2f} {mx:8.2f} {mean:6.2f} {share:6.0%} {blunt:>9}  {','.join(r['tools'])}{flag}")
edge = [r for r in rows if r["guide"] == "edge" and r["tools"]]
if edge:
    pulls = sorted(pull(r)[0] for r in edge)
    print(f"\nedge strokes with tools out: {len(edge)}, median max pull {pulls[len(pulls)//2]:.2f} mm, worst {pulls[-1]:.2f} mm")
