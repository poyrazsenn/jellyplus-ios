#!/usr/bin/env python3
"""Poyraz Tema eklenti deposunu (plugin-repo dalındaki manifest.json) günceller.
Kullanım (CI): python3 tool/update_plugin_manifest.py <repo> <sürüm> <zip yolu> <targetAbi>"""
import base64, datetime, hashlib, json, subprocess, sys

repo, ver, zp, abi = sys.argv[1:5]
GUID = '5eacc010-65b0-4df5-b3de-6958a110efcb'

def gh(*a, inp=None):
    return subprocess.run(['gh', 'api', *a], input=inp, capture_output=True, text=True, check=True).stdout

sha = None
try:
    cur = json.loads(gh(f'repos/{repo}/contents/manifest.json?ref=plugin-repo'))
    sha = cur['sha']
    man = json.loads(base64.b64decode(cur['content']).decode())
except subprocess.CalledProcessError:
    man = []

plug = next((p for p in man if p.get('guid') == GUID), None)
if plug is None:
    plug = {'guid': GUID, 'versions': []}
    man.append(plug)
plug.update({
    'name': 'Poyraz Tema',
    'description': 'Tema müziği olmayan film ve dizilere YouTube\'dan tema müziği bulur.',
    'overview': 'Themerr\'in boş bıraktığı yapımlar için YouTube\'da arar, en uygun sonucu theme.mp3 olarak indirir. Her gece çalışır; panodan elle bağlantı da verilebilir.',
    'owner': 'poyrazsenn',
    'category': 'General',
    'imageUrl': f'https://raw.githubusercontent.com/{repo}/plugin-repo/icon.png',
})
md5 = hashlib.md5(open(zp, 'rb').read()).hexdigest()
entry = {
    'version': ver,
    'changelog': f'Poyraz Tema {ver}',
    'targetAbi': abi,
    'sourceUrl': f'https://github.com/{repo}/releases/download/tema-v{ver}/poyraz-tema_{ver}.zip',
    'checksum': md5,
    'timestamp': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
}
plug['versions'] = [entry] + [v for v in plug.get('versions', []) if v.get('version') != ver][:4]

body = {
    'message': f'Poyraz Tema {ver}',
    'content': base64.b64encode(json.dumps(man, ensure_ascii=False, indent=2).encode()).decode(),
    'branch': 'plugin-repo',
}
if sha:
    body['sha'] = sha
gh('-X', 'PUT', f'repos/{repo}/contents/manifest.json', '--input', '-', inp=json.dumps(body))
print('Eklenti deposu güncellendi:', ver)
