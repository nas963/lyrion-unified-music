#!/usr/bin/env python3
"""Pravi paket za instalaciju: python build-release.py <verzija>

Rezultat je folder dist/ sa unifiedmusic.zip (prva instalacija preko get.sh), njegovim otiskom, skriptom
get.sh i UnifiedMusic-<verzija>.zip (samo plugin, za Lyrion-ov repozitorijum), i repo.xml u korenu repoa
(GitHub Pages: https://nas963.github.io/lyrion-unified-music/repo.xml). Preko repo.xml Lyrion sam azurira
plugin; commit-uje se repo.xml bas onog zip-a koji se objavljuje (svaki build menja SHA-1).
"""
import hashlib
import pathlib
import re
import sys
import time
import zipfile
from xml.sax.saxutils import escape

ROOT = pathlib.Path(__file__).resolve().parent.parent
PLUGIN = ROOT / 'src' / 'UnifiedMusic'
NAME = 'UnifiedMusic'
GITHUB = 'https://github.com/nas963/lyrion-unified-music'
# Vreme pravljenja, ne fiksni datum: LMS osvezava kes stringova samo kad strings.txt postane noviji.
BUILD_TIME = time.localtime()[:6]
TEXT_SUFFIXES = {'','.pm', '.txt', '.html', '.js', '.xml', '.sh', '.md', '.svg'}


def lf_bytes(path):
    data = path.read_bytes()
    if path.suffix in TEXT_SUFFIXES and b'\r' in data:
        raise SystemExit(f'CRLF u fajlu: {path}')
    return data


def main():
    if len(sys.argv) != 2 or not re.fullmatch(r'\d+\.\d+\.\d+', sys.argv[1]):
        raise SystemExit(__doc__)
    version = sys.argv[1]

    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    top = f'unifiedmusic-{version}'
    # Stalan naziv omogucava adresu /releases/latest/download/unifiedmusic.zip.
    target = dist / 'unifiedmusic.zip'
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as out:
        for name in ('install.sh', 'uninstall.sh', 'lms-repo.py', 'README.md', 'README.en.md'):
            out.writestr(f'{top}/{name}', lf_bytes(ROOT / 'packaging' / name))
        out.writestr(f'{top}/LICENSE', lf_bytes(ROOT / 'LICENSE'))
        plugin_files = []
        for path in sorted(PLUGIN.rglob('*')):
            if path.is_dir():
                continue
            data = lf_bytes(path)
            if path.name == 'install.xml' and path.parent == PLUGIN:
                data = re.sub(rb'<version>[^<]*</version>', b'<version>' + version.encode() + b'</version>', data)
            out.writestr(f'{top}/UnifiedMusic/{path.relative_to(PLUGIN).as_posix()}', data)
            plugin_files.append((path.relative_to(PLUGIN).as_posix(), data))
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    (dist / 'unifiedmusic.zip.sha256').write_text(f'{digest}  unifiedmusic.zip\n', encoding='ascii', newline='\n')
    (dist / 'get.sh').write_bytes(lf_bytes(ROOT / 'packaging' / 'get.sh'))
    print(target)

    # Zip za Lyrion-ov repozitorijum: folder UnifiedMusic/ (isti fajlovi kao u paketu), i repo.xml
    lms_zip = dist / f'{NAME}-{version}.zip'
    with zipfile.ZipFile(lms_zip, 'w', zipfile.ZIP_DEFLATED) as out:
        for rel, data in plugin_files + [('LICENSE', lf_bytes(ROOT / 'LICENSE'))]:
            info = zipfile.ZipInfo(f'{NAME}/{rel}', date_time=BUILD_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            out.writestr(info, data)
    sha1 = hashlib.sha1(lms_zip.read_bytes()).hexdigest()
    title, desc = strings('PLUGIN_UNIFIEDMUSIC'), strings('PLUGIN_UNIFIEDMUSIC_DESC')
    lines = [
        '<?xml version="1.0" encoding="utf-8"?>',
        '<extensions>',
        '  <details>',
        f'    <title lang="EN">{escape(title.get("EN", NAME))}</title>',
        '  </details>',
        '  <plugins>',
        f'    <plugin name="{NAME}" version="{version}" minTarget="8.0" maxTarget="*">',
    ]
    lines += [f'      <title lang="{l}">{escape(t)}</title>' for l, t in title.items()]
    lines += [f'      <desc lang="{l}">{escape(t)}</desc>' for l, t in desc.items()]
    lines += [
        '      <creator>nas963</creator>',
        '      <category>musicservices</category>',
        f'      <link>{GITHUB}</link>',
        f'      <url>{GITHUB}/releases/download/v{version}/{lms_zip.name}</url>',
        f'      <sha>{sha1}</sha>',
        '    </plugin>',
        '  </plugins>',
        '</extensions>',
        '',
    ]
    (ROOT / 'repo.xml').write_bytes(NL.join(lines).encode('utf-8'))
    print(f'{lms_zip}  sha1 {sha1}')


NL = chr(10)


def strings(key):
    """Tekst jednog kljuca iz strings.txt, po jeziku."""
    out, cur = {}, None
    for line in (PLUGIN / 'strings.txt').read_text(encoding='utf-8').splitlines():
        if line and not line[0].isspace():
            cur = line.strip()
        elif cur == key and line.strip():
            parts = line.strip().split(None, 1)
            if len(parts) == 2:
                out[parts[0]] = parts[1].strip()
    return out


if __name__ == '__main__':
    main()
