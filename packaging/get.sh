#!/usr/bin/env bash
# Preuzima poslednje izdanje Unified Music, proverava ga i pokrece instalaciju ili uklanjanje.
#   curl -fsSL https://github.com/nas963/lyrion-unified-music/releases/latest/download/get.sh | sudo bash
#   curl -fsSL https://github.com/nas963/lyrion-unified-music/releases/latest/download/get.sh | sudo bash -s uninstall
set -euo pipefail

BASE_URL="${UNIFIED_BASE_URL:-https://github.com/nas963/lyrion-unified-music/releases/latest/download}"
ACTION="${1:-install}"
case "$ACTION" in
    install|uninstall) ;;
    *) echo "Upotreba: get.sh [install|uninstall]"; exit 2 ;;
esac

command -v curl >/dev/null || { echo "Potreban je curl."; exit 1; }
command -v python3 >/dev/null || { echo "Potreban je python3."; exit 1; }
command -v sha256sum >/dev/null || { echo "Potreban je sha256sum."; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

download() {
    if ! curl -fsSL "$BASE_URL/$1" -o "$WORK/$1"; then
        echo "Nije moguće preuzeti $1 sa $BASE_URL."
        echo "Proveri internet vezu i da li je repo javan."
        exit 1
    fi
}

download unifiedmusic.zip
download unifiedmusic.zip.sha256

if ! (cd "$WORK" && sha256sum -c --status unifiedmusic.zip.sha256); then
    echo "Provera paketa nije uspela: preuzeti fajl nije ispravan. Ništa nije instalirano."
    exit 1
fi

python3 -m zipfile -e "$WORK/unifiedmusic.zip" "$WORK/package" >/dev/null
SCRIPT="$(find "$WORK/package" -maxdepth 2 -type f -name "$ACTION.sh" | head -n 1)"
[ -n "$SCRIPT" ] || { echo "U paketu nema skripte $ACTION.sh."; exit 1; }

bash "$SCRIPT"
