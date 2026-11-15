#!/usr/bin/env python3
"""NOT from the docs. Turn the docs page's `cat <<EOF >file ... EOF` heredocs into one directory per example,
files VERBATIM, so every example can be run with `kubectl kustomize <dir>`.
   extract-examples.py <kustomization.md> <outdir>
Grouping rule: a new example starts with the first heredoc after a root kustomization.yaml was written,
or at `mkdir base`, or at a new `##` section. Quoted delimiters (cat <<'EOF') are supported. Directory names come from the nearest heading."""
import os, re, sys
src, out = sys.argv[1], sys.argv[2]
lines = open(src).read().splitlines()
examples, cur, heading, root_k = [], None, "intro", False
i = 0
def new(name):
    global cur, root_k
    cur = {"name": name, "files": []}; examples.append(cur); root_k = False
while i < len(lines):
    l = lines[i]
    if l.startswith("#"):
        if re.match(r"^#{2,4} ", l):
            heading = re.sub(r"[^a-z0-9]+", "-", re.sub(r"\{.*?\}", "", l.lstrip("#").strip().lower())).strip("-")
            if l.startswith("## "):
                root_k = True          # a new top-level section always starts a new example
    if l.strip() == "mkdir base":
        new(heading)
    m = re.match(r"^\s*cat <<'?EOF'?\s*>\s*(\S+)\s*$", l)
    if m:
        path = re.sub(r"^\./", "", m.group(1))
        if cur is None or root_k:
            new(heading)
        body, i = [], i + 1
        while lines[i].strip() != "EOF":
            body.append(lines[i]); i += 1
        indent = min((len(b) - len(b.lstrip()) for b in body if b.strip()), default=0)
        cur["files"].append((path, "\n".join(b[indent:] for b in body) + "\n"))
        if path == "kustomization.yaml":
            root_k = True
    i += 1
for n, ex in enumerate(examples, 1):
    d = os.path.join(out, f"{n:02d}-{ex['name']}")
    for path, body in ex["files"]:
        os.makedirs(os.path.dirname(os.path.join(d, path)) or d, exist_ok=True)
        open(os.path.join(d, path), "w").write(body)   # later writes of the same file win, as when following the page
    print(d, " ".join(p for p, _ in ex["files"]))
