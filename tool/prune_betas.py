#!/usr/bin/env python3
"""Eski betaları siler (sürüm + etiket). Sadece 'prerelease' olanlara dokunur ve
yalnızca şu an derlenen sürümden ESKİ olanları siler; kararlı sürümler hiç silinmez.
Kullanım (CI): python3 tool/prune_betas.py <repo> <şimdiki sürüm>"""
import json, re, subprocess, sys

repo, cur = sys.argv[1], sys.argv[2]

def key(v):
    v = v.lstrip('v')
    core, _, pre = v.partition('-')
    nums = [int(x) for x in (core.split('.') + ['0', '0'])[:3]]
    if not pre:
        return nums + [9, 0]  # kararlı en yenisi
    rank = 3 if pre.startswith('rc') else 2 if pre.startswith('beta') else 1 if pre.startswith('alpha') else 0
    m = re.search(r'(\d+)$', pre)
    return nums + [rank, int(m.group(1)) if m else 0]

out = subprocess.run(['gh', 'api', f'repos/{repo}/releases?per_page=100', '--paginate'],
                     capture_output=True, text=True, check=True).stdout
rels = json.loads(out.replace('][', ','))
for r in rels:
    tag = r['tag_name']
    if not r.get('prerelease') or tag == f'v{cur}' or key(tag) >= key(cur):
        continue
    subprocess.run(['gh', 'release', 'delete', tag, '-R', repo, '--cleanup-tag', '-y'], check=False)
    print('silindi:', tag)
