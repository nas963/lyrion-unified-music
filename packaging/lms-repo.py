#!/usr/bin/env python3
"""Upis plugina i njegovog repozitorijuma u LMS prefs/plugin/extensions.prefs.

    python3 lms-repo.py add <extensions.prefs> <Ime> <repo.xml url>
    python3 lms-repo.py remove <extensions.prefs> <Ime> <repo.xml url>

"plugin:" je spisak plugina koje LMS vodi kao instalirane iz repozitorijuma, a "repos:" dodatni
repozitorijumi. Posle "add" LMS plugin azurira sam (Podesavanja > Plugins), kao bilo koji drugi.
LMS mora da stoji dok se fajl menja (pri gasenju upisuje svoje prefs). Ostale linije se ne diraju.
Isti fajl je u AudioCD, AudioIn i Unified Music paketu.
"""
import os
import re
import sys


def block(lines, key, cont):
    """(start, end) bloka "key:" sa linijama koje ga nastavljaju, ili (None, None)."""
    for i, l in enumerate(lines):
        if re.match(r'^%s:' % key, l):
            end = i + 1
            while end < len(lines) and cont(lines[end]):
                end += 1
            return i, end
    return None, None


def main():
    if len(sys.argv) != 5 or sys.argv[1] not in ('add', 'remove'):
        raise SystemExit(__doc__)
    action, path, name, repo = sys.argv[1:5]
    lines = open(path, encoding='utf-8').read().splitlines() if os.path.exists(path) else []
    if not lines:
        lines = ['---', '_version: 4', 'auto: 0', 'plugin: {}', 'repos: []', 'useUnsupported: 0']

    # plugin: { Ime: 1, ... } (kao mapa ispod kljuca; "{}" kad je prazno)
    start, end = block(lines, 'plugin', lambda l: l.startswith((' ', '\t')))
    have = {}
    if start is not None:
        for l in lines[start + 1:end]:
            m = re.match(r'^\s+([^:\s]+):\s*(.*)$', l)
            if m:
                have[m.group(1)] = m.group(2).strip() or '1'
    if action == 'add':
        have[name] = '1'
    else:
        have.pop(name, None)
    new = ['plugin:'] + ['  %s: %s' % (n, have[n]) for n in sorted(have)] if have else ['plugin: {}']
    if start is None:
        lines += new
    else:
        lines[start:end] = new

    # repos: [ url, ... ] (u jednoj liniji "[...]" ili kao "- url" ispod)
    start, end = block(lines, 'repos', lambda l: l.startswith((' ', '\t', '-')))
    repos = []
    if start is not None:
        inline = lines[start].split(':', 1)[1].strip()
        if inline not in ('', '[]'):
            repos += [r.strip().strip('\'"') for r in inline.strip('[]').split(',') if r.strip()]
        repos += [re.sub(r'^\s*-\s*', '', l).strip().strip('\'"') for l in lines[start + 1:end] if l.strip()]
    if action == 'add' and repo not in repos:
        repos.append(repo)
    if action == 'remove':
        repos = [r for r in repos if r != repo]
    new = ['repos:'] + ['- %s' % r for r in repos] if repos else ['repos: []']
    if start is None:
        lines += new
    else:
        lines[start:end] = new

    tmp = path + '.new'
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')
    if os.path.exists(path):
        st = os.stat(path)
        os.chmod(tmp, st.st_mode & 0o7777)
        if hasattr(os, 'chown'):
            try:
                os.chown(tmp, st.st_uid, st.st_gid)
            except PermissionError:
                pass
    os.replace(tmp, path)


if __name__ == '__main__':
    main()
