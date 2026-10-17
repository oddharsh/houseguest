import json, glob, re, statistics as st, sys, os
d = sys.argv[1]
OUT = {"CONTRIBUTOR","FIRST_TIME_CONTRIBUTOR","FIRST_TIMER","NONE"}
def clean(b):
    b = b or ""
    b = re.sub(r"<!--.*?-->", "", b, flags=re.S)
    b = re.sub(r"^\s*-\s*\[[ xX]\].*$", "", b, flags=re.M)   # checklists
    return b.strip()
def load(era):
    rows=[]
    for f in glob.glob(f"{d}/{era}_*.json"):
        repo=os.path.basename(f)[len(era)+1:-5]
        try: data=json.load(open(f))
        except Exception: continue
        for p in data:
            login=(p.get("author") or {}).get("login","")
            if p.get("authorAssociation") not in OUT or "bot" in login.lower(): continue
            p["repo"]=repo; p["clean"]=clean(p.get("body")); rows.append(p)
    return rows
EMOJI=re.compile("[\U0001F300-\U0001FAFF✅❌⚠✨]")
F = {
 "empty body": lambda b,t: len(b)==0,
 "has ## heading": lambda b,t: bool(re.search(r"^#{1,4} ", b, re.M)),
 "'## Summary'-style heading": lambda b,t: bool(re.search(r"^#{1,4} *(summary|overview|changes|motivation|description|what|why)", b, re.M|re.I)),
 "bullet list": lambda b,t: bool(re.search(r"^\s*[-*] ", b, re.M)),
 "code block": lambda b,t: "```" in b,
 "links issue (Fixes #/URL)": lambda b,t: bool(re.search(r"(fix(es|ed)?|close[sd]?|resolve[sd]?|ref(s)?|see)\s*:?\s*(#\d+|https://github\.com/\S+/(issues|pull)/\d+)", b, re.I)),
 "mentions testing": lambda b,t: bool(re.search(r"\b(test(s|ed|ing)?|repro\w*|verif\w+)\b", b, re.I)),
 "first person 'I'": lambda b,t: bool(re.search(r"(^|\s)I(\s|'m|'ve|'d)", b)),
 "hedge (I think/not sure/maybe/might)": lambda b,t: bool(re.search(r"\b(I think|not sure|I'm not|maybe|might|probably|unsure|I believe|feel free|happy to)\b", b, re.I)),
 "asks maintainer a question": lambda b,t: "?" in b,
 "thanks/sorry": lambda b,t: bool(re.search(r"\b(thanks|thank you|sorry)\b", b, re.I)),
 "em dash": lambda b,t: "\u2014" in b,
 "emoji": lambda b,t: bool(EMOJI.search(b)),
 "bold **": lambda b,t: "**" in b,
 "opens 'This PR'": lambda b,t: bool(re.match(r"(this (pr|pull request|change|commit))", b, re.I)),
 "AI vocab (ensure/comprehensive/robust/enhance/streamline/seamless)": lambda b,t: bool(re.search(r"\b(ensures?|comprehensive|robust|enhances?|streamlines?|seamless(ly)?|leverag\w+|utiliz\w+)\b", b, re.I)),
 "title: lowercase 'area: x' prefix": lambda b,t: bool(re.match(r"^[a-z0-9_./-]+(\([^)]*\))?!?: ", t)),
 "title: ends with period": lambda b,t: t.rstrip().endswith("."),
}
def pct(rows,fn): return 100*sum(1 for r in rows if fn(r["clean"],r["title"]))/max(1,len(rows))
def q(xs,p): xs=sorted(xs); return xs[int(p*(len(xs)-1))] if xs else 0
pre,post=load("pre"),load("post")
print(f"outside-contributor PRs: pre-2023 n={len(pre)}, mid-2025+ n={len(post)}\n")
for name,rows in (("pre",pre),("post",post)):
    L=[len(r["clean"]) for r in rows]; W=[len(r["clean"].split()) for r in rows if r["clean"]]
    sents=[len(s.split()) for r in rows for s in re.split(r"(?<=[.!?])\s+", re.sub(r"```.*?```","",r["clean"],flags=re.S)) if len(s.split())>2]
    print(f"{name}: body chars p25/med/p75 = {q(L,.25)}/{q(L,.5)}/{q(L,.75)}; words med {q(W,.5)}; mean sentence {st.mean(sents):.1f} words; title len med {q([len(r['title']) for r in rows],.5)}")
print(f"\n{'feature':66} {'pre':>6} {'post':>6}")
for k,fn in F.items(): print(f"{k:66} {pct(pre,fn):5.0f}% {pct(post,fn):5.0f}%")
print("\nmedian body chars by repo (pre -> post):")
repos=sorted({r['repo'] for r in pre+post})
for rp in repos:
    a=[len(r['clean']) for r in pre if r['repo']==rp]; b=[len(r['clean']) for r in post if r['repo']==rp]
    print(f"  {rp:22} {q(a,.5):5} (n={len(a):3}) -> {q(b,.5):5} (n={len(b):3})  headings {pct([r for r in pre if r['repo']==rp],F['has ## heading']):3.0f}% -> {pct([r for r in post if r['repo']==rp],F['has ## heading']):3.0f}%")
json.dump({"pre":pre,"post":post},open(f"{d}/filtered.json","w"))
