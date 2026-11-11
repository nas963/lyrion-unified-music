#!/usr/bin/env python3
"""Pravi paket za instalaciju: python build-release.py <verzija>

Rezultat je folder dist/ sa unifiedmusic.zip, njegovim otiskom i skriptom get.sh.
"""
import hashlib
import pathlib
import re
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
PLUGIN = ROOT / 'src' / 'UnifiedMusic'
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
        for name in ('install.sh', 'uninstall.sh', 'README.md'):
            out.writestr(f'{top}/{name}', lf_bytes(ROOT / 'packaging' / name))
        out.writestr(f'{top}/LICENSE', lf_bytes(ROOT / 'LICENSE'))
        for path in sorted(PLUGIN.rglob('*')):
            if path.is_dir():
                continue
            data = lf_bytes(path)
            if path.name == 'install.xml' and path.parent == PLUGIN:
                data = re.sub(rb'<version>[^<]*</version>', b'<version>' + version.encode() + b'</version>', data)
            out.writestr(f'{top}/UnifiedMusic/{path.relative_to(PLUGIN).as_posix()}', data)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    (dist / 'unifiedmusic.zip.sha256').write_text(f'{digest}  unifiedmusic.zip\n', encoding='ascii', newline='\n')
    (dist / 'get.sh').write_bytes(lf_bytes(ROOT / 'packaging' / 'get.sh'))
    print(target)


if __name__ == '__main__':
    main()
