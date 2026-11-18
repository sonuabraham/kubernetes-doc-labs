#!/usr/bin/env python3
"""Extract every ```yaml block of the docs page, verbatim, to docs-examples/BNN-<section>.yaml.
Usage: ./extract-examples.py <path to custom-resource-definitions.md>"""
import re, sys, os
lines = open(sys.argv[1]).read().split('\n')
os.makedirs('docs-examples', exist_ok=True)
sec, n, i = 'intro', 0, 0
while i < len(lines):
    l = lines[i]
    m = re.match(r'^#{2,4} (.*)', l)
    if m:
        sec = re.sub(r'[^a-z0-9]+', '-', re.sub(r'\{.*\}|`', '', m.group(1)).lower()).strip('-')[:30]
    f = re.match(r'^(\s*)```(\w*)', l)
    if f:
        ind, lang, j, body = len(f.group(1)), f.group(2), i + 1, []
        while not re.match(r'^\s*```\s*$', lines[j]):
            body.append(lines[j][ind:] if lines[j][:ind].strip() == '' else lines[j]); j += 1
        if lang == 'yaml':
            n += 1
            name = f'docs-examples/B{n:02d}-{sec}.yaml'
            open(name, 'w').write('\n'.join(body) + '\n')
            print(name)
        i = j
    i += 1
