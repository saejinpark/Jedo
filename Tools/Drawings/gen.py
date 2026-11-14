import json, math, random, sys
out=sys.argv[1]
def line(a,b,n=None,p=0.5):
    d=math.hypot(b[0]-a[0],b[1]-a[1]); n=n or max(int(d/2),1)
    return [[a[0]+(b[0]-a[0])*t/n, a[1]+(b[1]-a[1])*t/n, p] for t in range(n+1)]
def arc(c,r,a0,a1,p=0.5,n=None):
    n=n or max(int(abs(a1-a0)*r/1.5),6)
    return [[c[0]+r*math.cos(a0+(a1-a0)*t/n), c[1]+r*math.sin(a0+(a1-a0)*t/n), p] for t in range(n+1)]
def S(i,pts,g="HB"): return {"i":i,"g":g,"pts":pts}

# ---------- 1. floor plan, 1:50 on A3 landscape ----------
st=[]; k=1/50; ox,oy=110,70
def P(x,y): return (ox+x*k, oy+y*k)
T=200
def wall(axis, fixed, a, b, openings):
    # axis 'h': wall along x at y=fixed (centre line); 'v': along y at x=fixed
    cuts=[a]+[v for o in openings for v in o]+[b]
    for s,e in zip(cuts[0::2],cuts[1::2]):
        for off in (-T/2,T/2):
            p,q=((s,fixed+off),(e,fixed+off)) if axis=='h' else ((fixed+off,s),(fixed+off,e))
            st.append(S("m09",line(P(*p),P(*q),p=0.7),"2B"))
        for end in (s,e):
            p,q=((end,fixed-T/2),(end,fixed+T/2)) if axis=='h' else ((fixed-T/2,end),(fixed+T/2,end))
            st.append(S("m09",line(P(*p),P(*q),p=0.7),"2B"))
    return openings
W,H=9000,7000
# centre lines first, in a hard lead
for x in (0,5000,9000): st.append(S("m03",line(P(x,-900),P(x,H+900),p=0.35),"4H"))
for y in (0,3500,7000): st.append(S("m03",line(P(-900,y),P(W+900,y),p=0.35),"4H"))
wall('h',0,-T/2,W+T/2,[(1000,3000)])                 # top, window
wall('h',H,-T/2,W+T/2,[(2000,2900)])                 # bottom, entrance
wall('v',0,T/2,H-T/2,[(2500,4500)])                  # left, window
wall('v',W,T/2,H-T/2,[(1000,2500),(4500,6000)])      # right, windows
wall('v',5000,T/2,H-T/2,[(1500,2300),(4700,5500)])   # inner, two doors
wall('h',3500,5000+T/2,W-T/2,[(7600,8400)])          # inner, door
# windows: three fine lines across the opening
def window(axis,fixed,a,b):
    for off in (-T/2,0,T/2):
        p,q=((a,fixed+off),(b,fixed+off)) if axis=='h' else ((fixed+off,a),(fixed+off,b))
        st.append(S("m03",line(P(*p),P(*q),p=0.5),"H"))
window('h',0,1000,3000); window('v',0,2500,4500); window('v',W,1000,2500); window('v',W,4500,6000)
# doors: leaf and quarter swing
def door(hx,hy,leafdir,swingto,w=None):
    w=w or 900
    a0=math.atan2(leafdir[1],leafdir[0]); a1=math.atan2(swingto[1],swingto[0])
    if a1-a0>math.pi: a1-=2*math.pi
    if a0-a1>math.pi: a1+=2*math.pi
    st.append(S("m05",line(P(hx,hy),P(hx+leafdir[0]*w,hy+leafdir[1]*w),p=0.6),"HB"))
    c=P(hx,hy); st.append(S("m03",arc(c,w*k,a0,a1,p=0.4),"H"))
door(2000,H,(0,-1),(1,0),900)          # entrance swings in
door(5000,1500,(1,0),(0,1),800)        # to bedroom
door(5000,5500,(1,0),(0,-1),800)       # to kitchen
door(7600,3500,(0,1),(1,0),800)
# furniture, fine
def rect(x,y,w,h,i="m03",g="H",p=0.5):
    for a,b in (((x,y),(x+w,y)),((x+w,y),(x+w,y+h)),((x+w,y+h),(x,y+h)),((x,y+h),(x,y))): st.append(S(i,line(P(*a),P(*b),p=p),g))
rect(5400,300,2000,1500); rect(5400,300,2000,400)        # bed and pillow strip
rect(8300,3900,500,2800); st.append(S("m03",arc(P(8550,4600),200*k,0,2*math.pi,p=0.5),"H")); st.append(S("m03",arc(P(8550,5200),200*k,0,2*math.pi,p=0.5),"H"))  # counter, hobs
rect(600,5200,2200,900); rect(1000,3600,1400,800)          # sofa, table
# dimensions: line, ticks
def dim(a,b,off):
    horizontal = a[1]==b[1]
    p=(a[0],a[1]+off) if horizontal else (a[0]+off,a[1]); q=(b[0],b[1]+off) if horizontal else (b[0]+off,b[1])
    st.append(S("m03",line(P(*p),P(*q),p=0.45),"2H"))
    for e in (p,q):
        st.append(S("m05",line(P(e[0]-120,e[1]+120),P(e[0]+120,e[1]-120),p=0.6),"HB"))
        st.append(S("m03",line(P(*( (e[0],e[1]-250) if horizontal else (e[0]-250,e[1]) )),P(*((e[0],e[1]+250) if horizontal else (e[0]+250,e[1]))),p=0.4),"2H"))
dim((0,0),(5000,0),-600); dim((5000,0),(9000,0),-600); dim((0,0),(0,3500),-600); dim((0,3500),(0,7000),-600); dim((0,0),(9000,0),-1300)
# north arrow and scale bar
c=(ox+W*k+35,oy+20); st.append(S("m05",arc(c,9,0,2*math.pi),"HB")); st.append(S("m07",line((c[0],c[1]+9),(c[0],c[1]-13),p=0.6),"B")); st.append(S("m07",line((c[0],c[1]-13),(c[0]-4,c[1]-5),p=0.6),"B")); st.append(S("m07",line((c[0],c[1]-13),(c[0]+4,c[1]-5),p=0.6),"B"))
bx,by=ox,oy+H*k+32
st.append(S("m05",line((bx,by),(bx+100,by)),"HB"))
for i in range(6): st.append(S("m05",line((bx+20*i,by),(bx+20*i,by-(4 if i%5==0 else 2.5))),"HB"))
json.dump({"paper":"a3","landscape":True,"strokes":st},open(out+"/plan.json","w"))

# ---------- 2. basic skirt block, full size on A1 portrait ----------
st=[]; ox,oy=57,150
def Q(x,y): return (ox+x*10, oy+y*10)   # centimetres in
Wst,Hip,L,HL=68,92,60,19
tot=Hip/2+2; back=tot/2-0.5
for a,b in (((0,0),(tot,0)),((tot,0),(tot,L)),((tot,L),(0,L)),((0,L),(0,0)),((0,HL),(tot,HL)),((back,0),(back,L))):
    st.append(S("m03",line(Q(*a),Q(*b),p=0.35),"2H"))
def curve(p0,p1,p2,n=40): return [[(1-t)**2*p0[0]+2*(1-t)*t*p1[0]+t*t*p2[0], (1-t)**2*p0[1]+2*(1-t)*t*p1[1]+t*t*p2[1], 0.6] for t in [i/n for i in range(n+1)]]
bw=Wst/4-0.5+3; fw=Wst/4+0.5+2.5
bside=Q(bw,-1.2); fside=Q(tot-fw,-1.2)
# side seams: hip curve from waist to hip line, then straight to hem
st.append(S("m07",curve(bside,Q(back-0.3,8),Q(back,HL)),"HB")); st.append(S("m07",line(Q(back,HL),Q(back,L),p=0.6),"HB"))
st.append(S("m07",curve(fside,Q(back+0.3,8),Q(back,HL)),"HB"))
# waist: dips at centre back, level at centre front
st.append(S("m07",curve(Q(0,1),Q(bw/2,0.6),bside),"HB")); st.append(S("m07",curve(Q(tot,0),Q(tot-fw/2,0),fside),"HB"))
# centre back, centre front, hem
st.append(S("m07",line(Q(0,1),Q(0,L),p=0.6),"HB")); st.append(S("m07",line(Q(tot,0),Q(tot,L),p=0.6),"HB")); st.append(S("m07",line(Q(0,L),Q(tot,L),p=0.6),"HB"))
# darts
def dart(cx,w,l,top):
    st.append(S("m05",line(Q(cx-w/2,top),Q(cx,top+l),p=0.55),"HB")); st.append(S("m05",line(Q(cx+w/2,top),Q(cx,top+l),p=0.55),"HB"))
    st.append(S("m03",line(Q(cx,top-0.5),Q(cx,top+l+1),p=0.35),"2H"))
dart(bw/2,3,12,0.3); dart(tot-fw/2,2.5,9,-0.3)
# grain lines with arrowheads
for gx in (back/2, back+(tot-back)/2):
    st.append(S("m05",line(Q(gx,25),Q(gx,50),p=0.5),"HB"))
    for yy,d in ((25,1),(50,-1)):
        st.append(S("m05",line(Q(gx,yy),Q(gx-0.6,yy+1.5*d),p=0.5),"HB")); st.append(S("m05",line(Q(gx,yy),Q(gx+0.6,yy+1.5*d),p=0.5),"HB"))
# notches at the hip line on the side seam
st.append(S("m05",line(Q(back-0.6,HL),Q(back+0.6,HL),p=0.7),"B"))
json.dump({"paper":"a1","landscape":False,"strokes":st},open(out+"/skirt.json","w"))

# ---------- 3. manga page on B4 ----------
random.seed(7); st=[]
x0,x1,y0,y1=53.5,203.5,72,292
def frame(a,b,c,d):
    for p,q in (((a,b),(c,b)),((c,b),(c,d)),((c,d),(a,d)),((a,d),(a,b))): st.append(S("p07",line(p,q)))
frame(x0,y0,x1,190); frame(x0,196,125,y1); frame(131,196,x1,y1)
# top panel: focus lines to the middle, tapering in; a balloon left white
cx,cy=128.5,131; bal=(86,96,24,15)
def inside_balloon(x,y): return ((x-bal[0])/(bal[2]+1.5))**2+((y-bal[1])/(bal[3]+1.5))**2<1
for n in range(150):
    a=random.uniform(0,2*math.pi); dx,dy=math.cos(a),math.sin(a)
    # where the ray leaves the panel
    t=min((x1-cx)/dx if dx>0 else (x0-cx)/dx if dx<0 else 1e9, (190-cy)/dy if dy>0 else (y0-cy)/dy if dy<0 else 1e9)
    r_in=random.uniform(30,46); pts=[]
    m=24
    for j in range(m+1):
        r=t-(t-r_in)*j/m; x,y=cx+dx*r,cy+dy*r
        if inside_balloon(x,y): break
        pts.append([x,y,0.75*(1-j/m)**1.4+0.02])
    if len(pts)>3: st.append(S("g",pts))
st.append(S("g",[[bal[0]+bal[2]*math.cos(t),bal[1]+bal[3]*math.sin(t),0.5] for t in [i*2*math.pi/60 for i in range(61)]]))
st.append(S("g",[[100,108,0.5],[106,119,0.35],[94,110,0.5]]))
# a face in the clearing: head, hair, eyes, mouth
st.append(S("g",arc((cx,cy+2),19,math.radians(-20),math.radians(200),p=0.5)))
hair=[]; 
for i in range(9):
    a=math.radians(200+i*17.5); hair+= [[cx+19*math.cos(a),cy+2+19*math.sin(a),0.6],[cx+(27 if i%2==0 else 22)*math.cos(a+0.15),cy+2+(27 if i%2==0 else 22)*math.sin(a+0.15),0.15]]
st.append(S("g",hair))
for ex in (-8,8):
    st.append(S("g",[[cx+ex-4,cy,0.3],[cx+ex,cy-2.5,0.75],[cx+ex+4,cy,0.3]])); st.append(S("g",arc((cx+ex,cy+1.5),1.6,0,2*math.pi,p=0.8,n=14)))
st.append(S("maru",[[cx-4,cy+11,0.3],[cx,cy+12.5,0.6],[cx+5,cy+10.5,0.2]]))
# bottom left: speed lines, flicked from the right
for n in range(46):
    y=random.uniform(199,289); l=random.uniform(18,62); xs=122
    st.append(S("g",[[xs-l*j/14, y, 0.7*(1-j/14)**1.2+0.02] for j in range(15)]))
# bottom right: cross-hatching that thins toward the top
for n in range(70):
    yb=random.uniform(205,290); xb=random.uniform(133,199); l=random.uniform(5,11)*(0.4+0.6*(yb-196)/96)
    if random.random()<(yb-196)/96+0.15:
        st.append(S("maru",[[xb,yb,0.45],[min(xb+l,202),yb-l,0.35]])); 
        if random.random()<(yb-230)/60: st.append(S("maru",[[xb,yb-l,0.45],[min(xb+l,202),yb,0.35]]))
json.dump({"paper":"b4","landscape":False,"strokes":st},open(out+"/manga.json","w"))
print("ok")
