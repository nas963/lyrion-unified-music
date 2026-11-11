#!/usr/bin/env bash
# Uklanja plugin Unified Music. Pokrece se kao root:
#   sudo bash uninstall.sh
# Restartuje Lyrion. Material Skin ostaje, a miksovi i podesavanja ostaju na disku.
set -euo pipefail

PREFS=/var/lib/squeezeboxserver/prefs
UNIFIED=/usr/share/squeezeboxserver/Plugins/UnifiedMusic
CUSTOM="$PREFS/material-skin/custom.js"

[ "$(id -u)" -eq 0 ] || { echo "Pokreni kao root: sudo bash uninstall.sh"; exit 1; }

systemctl stop lyrionmusicserver
rm -rf "$UNIFIED"
if [ -f "$CUSTOM" ]; then
    sed -i '/UnifiedMusic start/,/UnifiedMusic end/d' "$CUSTOM"
fi
rm -f "$PREFS/material-skin/images/folder-local.svg"
systemctl start lyrionmusicserver
systemctl is-active lyrionmusicserver
echo "UKLONJENO"
