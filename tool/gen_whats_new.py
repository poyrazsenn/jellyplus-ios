#!/usr/bin/env python3
"""RELEASE_NOTES.md'deki "Yenilikler" maddelerinden lib/whats_new.g.dart üretir.

Madde biçimi:  - **Başlık:** açıklama
"Yenilikler" bölümü yoksa (ör. sadece düzeltme içeren 2.1.1) liste boş kalır ve
uygulama yenilikler penceresini göstermez.
Derlemede (GitHub Actions) otomatik çalışır; elle çalıştırmak için: python3 tool/gen_whats_new.py
"""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
notes = (root / 'RELEASE_NOTES.md').read_text(encoding='utf-8').splitlines()

# anahtar kelime → Material simgesi (ilk eşleşen kazanır)
ICONS = [
    (r'keşfet', 'explore'),
    (r'önizleme', 'preview'),
    (r'ortak ayarlar', 'sync'),
    (r'kararlılık', 'speed'),
    (r'sidestore', 'update'),
    (r'güncelleme bildirimi', 'update'),
    (r'koleksiyon', 'library'),
    (r'top 10|popüler', 'top'),
    (r'yakında|takvim', 'calendar'),
    (r'seri sırası', 'order'),
    (r'gece modu', 'night'),
    (r'indir|çevrimdışı|offline', 'download'),
    (r'seerr|iste[kğ]', 'request'),
    (r'önizleme|trickplay|fragman', 'preview'),
    (r'sonraki|bölüm', 'next'),
    (r'altyazı', 'subtitles'),
    (r'ipad|tablet|ekran|arayüz|tasarım', 'layout'),
    (r'oyuncu|kişi', 'person'),
    (r'tara|kütüphane', 'library'),
    (r'sürüm|güncelle', 'update'),
    (r'ses|müzik', 'audio'),
    (r'hız|performans', 'speed'),
]


def icon_for(text: str) -> str:
    t = text.lower()
    for pat, key in ICONS:
        if re.search(pat, t):
            return key
    return 'star'


def clean(s: str) -> str:
    s = re.sub(r'\*\*(.+?)\*\*', r'\1', s)
    s = s.replace('`', '')
    s = re.sub(r'\[(.+?)\]\(.+?\)', r'\1', s)
    return s.strip()


def dart(s: str) -> str:
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$').replace('\n', ' ') + "'"


items = []
inside = False
for line in notes:
    st = line.strip()
    if re.fullmatch(r'(#+\s*)?\**\s*Yenilikler\s*\**:?', st, re.I):
        inside = True
        continue
    if not inside:
        continue
    if st.startswith(('- ', '* ')):
        body = st[2:].strip()
        m = re.match(r'\*\*(.+?)\*\*\s*:?\s*(.*)', body)
        if m:
            title = clean(m.group(1)).rstrip(':').strip()
            desc = clean(m.group(2)).lstrip(':').strip()
        else:
            title, desc = clean(body), ''
        ic = icon_for(title)
        items.append((ic if ic != 'star' else icon_for(desc), title, desc))
    elif st == '' and items:
        continue
    elif st:
        if items or st.startswith(('#', '**')):
            break

out = ['// OTOMATİK ÜRETİLDİ: tool/gen_whats_new.py, RELEASE_NOTES.md\'den. Elle düzenleme;',
       '// sürüm notlarını RELEASE_NOTES.md\'de yaz, derleme bu dosyayı yeniden üretir.',
       '',
       '/// [simge anahtarı, başlık, açıklama]',
       'const kWhatsNew = <List<String>>[']
for ic, t, d in items:
    out.append(f'  [{dart(ic)}, {dart(t)}, {dart(d)}],')
out.append('];')
(root / 'lib' / 'whats_new.g.dart').write_text('\n'.join(out) + '\n', encoding='utf-8')
print(f'{len(items)} yenilik yazıldı', file=sys.stderr)
