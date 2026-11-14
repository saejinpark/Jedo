import sys, struct, json, math, time
src, out, paper, landscape, pen = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]=="1", sys.argv[5]
b=open(src,'rb').read()
off=struct.unpack_from('<I',b,10)[0]; w,h=struct.unpack_from('<ii',b,18); bpp=struct.unpack_from('<H',b,28)[0]
flip=h>0; h=abs(h); n=bpp//8; row=(w*n+3)//4*4
def lum(x,y):
    yy=h-1-y if flip else y
    i=off+yy*row+x*n
    return (b[i]+b[i+1]+b[i+2])//3 if n>=3 else b[i]
vals=[[lum(x,y) for x in range(w)] for y in range(h)]
flat=sorted(v for r in vals for v in r); bg=flat[len(flat)*3//4]
thr=min(bg-45, 150)
dark=set((x,y) for y in range(h) for x in range(w) if vals[y][x]<thr)
print('size',w,h,'bg',bg,'thr',thr,'dark',len(dark), flush=True)
# Zhang-Suen thinning
def nb(x,y): return [(x,y-1),(x+1,y-1),(x+1,y),(x+1,y+1),(x,y+1),(x-1,y+1),(x-1,y),(x-1,y-1)]
sk=set(dark); t=time.time()
while True:
    changed=False
    for step in (0,1):
        rm=[]
        for (x,y) in sk:
            P=[p in sk for p in nb(x,y)]
            B=sum(P)
            if B<2 or B>6: continue
            A=sum(1 for i in range(8) if not P[i] and P[(i+1)%8])
            if A!=1: continue
            if step==0:
                if P[0] and P[2] and P[4]: continue
                if P[2] and P[4] and P[6]: continue
            else:
                if P[0] and P[2] and P[6]: continue
                if P[0] and P[4] and P[6]: continue
            rm.append((x,y))
        if rm: changed=True; sk.difference_update(rm)
    if not changed: break
print('skeleton',len(sk),'%.1fs'%(time.time()-t), flush=True)
# thickness of the original line at a skeleton pixel: how far dark reaches
def thick(x,y):
    r=0
    while r<6 and all(((x+dx,y+dy) in dark) for dx,dy in ((r+1,0),(-r-1,0),(0,r+1),(0,-r-1))): r+=1
    return r
# walk the skeleton into polylines
left=set(sk); lines=[]
def degree(p): return sum(1 for q in nb(*p) if q in left)
while left:
    ends=[p for p in left if degree(p)==1]
    start=ends[0] if ends else next(iter(left))
    # prefer walking from line ends: collect all ends once per sweep
    for start in (ends or [start]):
        if start not in left: continue
        path=[start]; left.discard(start); cur=start
        while True:
            nxt=[q for q in nb(*cur) if q in left]
            if not nxt: break
            # keep going straight where it can
            if len(path)>1:
                dx,dy=cur[0]-path[-2][0],cur[1]-path[-2][1]
                nxt.sort(key=lambda q: -((q[0]-cur[0])*dx+(q[1]-cur[1])*dy))
            cur=nxt[0]; left.discard(cur); path.append(cur)
        if len(path)>=4: lines.append(path)
print('lines',len(lines), flush=True)
# onto the print: the picture's long side is 152 mm, centred on the paper
PW,PH={'a3':(297,420),'b4':(257,364),'a4':(210,297)}[paper]
if landscape: PW,PH=PH,PW
k=152.0/max(w,h); ox=PW/2-w*k/2; oy=PH/2-h*k/2
st=[]
for path in lines:
    pts=[]
    for j,(x,y) in enumerate(path):
        if j%2 and j!=len(path)-1: continue
        pts.append([round(ox+(x+0.5)*k,3), round(oy+(y+0.5)*k,3), round(min(0.25+0.16*thick(x,y),0.95),2)])
    st.append({"i":pen,"g":"HB","pts":pts})
json.dump({"paper":paper,"landscape":landscape,"photo":src.split('/')[-1].replace('.bmp','.jpg'),"photoAt":[PW/2,PH/2],"tracing":True,"strokes":st},open(out,'w'))
print('strokes',len(st),'points',sum(len(s['pts']) for s in st))
