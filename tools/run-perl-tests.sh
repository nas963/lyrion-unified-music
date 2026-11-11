#!/usr/bin/env bash
# Kopira plugin i testove u ~/unifiedmusic-test na serveru i pokrece ih.
# Zivi plugin i Lyrion se ne diraju.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REMOTE=unifiedmusic-test

ssh -o BatchMode=yes lyrion "rm -rf ~/$REMOTE && mkdir -p ~/$REMOTE/lib/Plugins ~/$REMOTE/t"
if [ -d "$ROOT/src/UnifiedMusic" ]; then
    scp -q -r "$ROOT/src/UnifiedMusic" "lyrion:$REMOTE/lib/Plugins/"
fi
scp -q "$ROOT"/tests/perl/*.t "lyrion:$REMOTE/t/"
scp -q -r "$ROOT/tests/fixtures" "lyrion:$REMOTE/t/"
scp -q -r "$ROOT/packaging" "lyrion:$REMOTE/"
ssh -o BatchMode=yes lyrion "cd ~/$REMOTE && prove -r -I lib ${1:-t}"
