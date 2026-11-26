#!/usr/bin/env python3
"""Yeni sürüm yayınlanınca SideStore kaynağına (sidestore dalı) ekler.
Kullanım (CI): python3 tool/update_sidestore.py <repo> <ver> <ipa yolu>"""
import base64, datetime, json, os, re, subprocess, sys

repo, ver, ipa = sys.argv[1], sys.argv[2], sys.argv[3]

def gh(*args, inp=None):
    return subprocess.run(['gh', 'api', *args], input=inp, capture_output=True, text=True, check=True).stdout

cur = json.loads(gh(f'repos/{repo}/contents/sidestore.json?ref=sidestore'))
src = json.loads(base64.b64decode(cur['content']).decode())

pub = open('pubspec.yaml').read()
m = re.search(r'^version:\s*([0-9.]+)\+(\d+)', pub, re.M)
short, build = m.group(1), m.group(2)

def pretty(v):
    core, _, pre = v.partition('-')
    p = core.split('.')
    s = '.'.join(p[:2]) if len(p) > 2 and p[2] == '0' else core
    return f"{s} {pre.replace('.', ' ')}".strip()

notes = open('RELEASE_NOTES.md').read()
desc = ''
if '**Yenilikler**' in notes:
    a = notes.index('**Yenilikler**')
    b = notes.find('\n**', a + 16)
    items = re.findall(r'^- \*\*(.+?):?\*\*\s*(.*)$', notes[a:b if b > 0 else None], re.M)
    desc = '\n'.join(f"• {t.rstrip(':')}: {d}" for t, d in items)

entry = {
    'version': ver,  # IPA'daki CFBundleShortVersionString ile aynı
    'buildVersion': build,
    'marketingVersion': pretty(ver),
    'date': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'localizedDescription': desc,
    'downloadURL': f'https://github.com/{repo}/releases/download/v{ver}/JellyPlus.ipa',
    'size': os.path.getsize(ipa),
    'minOSVersion': '14.0',
}
app = src['apps'][0]
app['versions'] = [entry]  # eski betalar desteklenmiyor: kaynakta sadece en yeni sürüm

body = json.dumps({
    'message': f'SideStore kaynağı: Poyraz Player {pretty(ver)}',
    'content': base64.b64encode(json.dumps(src, ensure_ascii=False, indent=2).encode()).decode(),
    'sha': cur['sha'],
    'branch': 'sidestore',
})
gh('-X', 'PUT', f'repos/{repo}/contents/sidestore.json', '--input', '-', inp=body)
print('SideStore kaynağı güncellendi:', pretty(ver))
