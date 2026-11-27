#!/usr/bin/env bash
# Uklanja plugin Unified Music. Pokrece se kao root:
#   sudo bash uninstall.sh
# Restartuje Lyrion. Material Skin ostaje, a miksovi i podesavanja ostaju na disku.
set -euo pipefail

STAGE="$(cd "$(dirname "$0")" && pwd)"
PREFS=/var/lib/squeezeboxserver/prefs
UNIFIED="/var/lib/squeezeboxserver/cache/InstalledPlugins/Plugins/UnifiedMusic /usr/share/squeezeboxserver/Plugins/UnifiedMusic /var/lib/squeezeboxserver/Plugins/UnifiedMusic"
EXT_PREFS="$PREFS/plugin/extensions.prefs"
REPO_URL=https://nas963.github.io/lyrion-unified-music/repo.xml
CUSTOM="$PREFS/material-skin/custom.js"

[ "$(id -u)" -eq 0 ] || { echo "Pokreni kao root: sudo bash uninstall.sh"; exit 1; }

systemctl stop lyrionmusicserver
for d in $UNIFIED; do rm -rf "$d"; done
if [ -f "$EXT_PREFS" ] && [ -f "$STAGE/lms-repo.py" ]; then
    python3 "$STAGE/lms-repo.py" remove "$EXT_PREFS" UnifiedMusic "$REPO_URL"
fi
if [ -f "$CUSTOM" ]; then
    sed -i '/UnifiedMusic start/,/UnifiedMusic end/d' "$CUSTOM"
fi
rm -f "$PREFS/material-skin/images/folder-local.svg"
systemctl start lyrionmusicserver
systemctl is-active lyrionmusicserver
echo "UKLONJENO"
