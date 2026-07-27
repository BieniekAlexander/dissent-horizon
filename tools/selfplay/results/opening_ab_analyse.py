import json, statistics as st

def load(p):
    return [json.loads(l) for l in open(p)]

def traj(rows):
    """One entry per slot per match: the sample series for that slot."""
    out=[]
    for r in rows:
        for i in range(2):
            out.append([s["slots"][i] for s in r["samples"]])
    return out

def first_time(rows, key, thresh=1):
    """Simulated seconds at which `key` first reaches thresh, per slot-trajectory."""
    res=[]
    for r in rows:
        for i in range(2):
            t=None
            for s in r["samples"]:
                if s["slots"][i].get(key,0) >= thresh:
                    t=s["simulated_seconds"]; break
            res.append(t)
    return res

def series(rows, key, times):
    """Mean of `key` across slot-trajectories at each sampled time."""
    out={}
    for t in times:
        vals=[]
        for r in rows:
            for i in range(2):
                for s in r["samples"]:
                    if abs(s["simulated_seconds"]-t) < 0.6:
                        vals.append(s["slots"][i].get(key,0)); break
        out[t]=st.mean(vals) if vals else None
    return out

def peak(rows, key):
    res=[]
    for r in rows:
        for i in range(2):
            res.append(max(s["slots"][i].get(key,0) for s in r["samples"]))
    return res

B=load("before.jsonl"); A=load("after.jsonl")
TIMES=[60,120,180,240,300,360]

print("matches: before=%d after=%d   slot-trajectories: %d / %d" % (len(B),len(A),2*len(B),2*len(A)))
print()
for name,key,thresh in [("FIRST INCOME STRUCTURE CLAIMED (site taken)","income_structure_count",1),
                        ("FIRST EXTRACTOR FINISHED","extractor_count",1),
                        ("SECOND EXTRACTOR FINISHED","extractor_count",2),
                        ("THIRD EXTRACTOR FINISHED","extractor_count",3)]:
    print(name)
    for label,rows in (("before",B),("after",A)):
        v=first_time(rows,key,thresh)
        got=[x for x in v if x is not None]
        s = ("mean %.1f s  min %.0f  max %.0f  n=%d/%d" % (st.mean(got),min(got),max(got),len(got),len(v))) if got else "never, n=0/%d"%len(v)
        print("   %-7s %s" % (label,s))
    print()

for name,key in [("EXTRACTORS (finished) over time","extractor_count"),
                 ("INCOME STRUCTURES (incl. building) over time","income_structure_count"),
                 ("UTILITY UNITS over time","utility_unit_count"),
                 ("UNITS over time","unit_count"),
                 ("ARMY ENERGY VALUE over time","army_energy_value"),
                 ("STRUCTURES over time","structure_count"),
                 ("ENERGY over time","energy")]:
    print(name)
    sb=series(B,key,TIMES); sa=series(A,key,TIMES)
    print("   t(s)   " + "".join("%9d"%t for t in TIMES))
    print("   before " + "".join("%9.2f"%sb[t] for t in TIMES))
    print("   after  " + "".join("%9.2f"%sa[t] for t in TIMES))
    print()

print("PEAKS (mean over slot-trajectories)")
for key in ["extractor_count","utility_unit_count","unit_count","structure_count"]:
    print("   %-22s before %6.2f   after %6.2f" % (key, st.mean(peak(B,key)), st.mean(peak(A,key))))
