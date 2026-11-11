#!/usr/bin/env bash
# Instalira plugin Unified Music. Pokrece se kao root iz raspakovanog paketa:
#   sudo bash install.sh
# Restartuje Lyrion, sto prekida reprodukciju na svim plejerima.
set -euo pipefail

STAGE="$(cd "$(dirname "$0")" && pwd)"
PLUGINS=/var/lib/squeezeboxserver/cache/InstalledPlugins/Plugins
MATERIAL="$PLUGINS/MaterialSkin"
UNIFIED_DIR=/usr/share/squeezeboxserver/Plugins
UNIFIED="$UNIFIED_DIR/UnifiedMusic"
OLD_BACKUP_POINTER=/var/lib/squeezeboxserver/backup-f1-latest

[ "$(id -u)" -eq 0 ] || { echo "Pokreni kao root: sudo bash install.sh"; exit 1; }
command -v systemctl >/dev/null || { echo "Paket je za Debian/Ubuntu sa systemd-om."; exit 1; }
systemctl cat lyrionmusicserver >/dev/null 2>&1 || { echo "Nije nadjen servis lyrionmusicserver."; exit 1; }
[ -f "$STAGE/UnifiedMusic/install.xml" ] || { echo "Nema plugina u $STAGE"; exit 1; }
[ -d "$MATERIAL" ] || { echo "Prvo instaliraj Material Skin iz Lyrion podesavanja."; exit 1; }

RESTORE=""
if grep -q '<version>900\.' "$MATERIAL/install.xml"; then
    RESTORE="$(cat "$OLD_BACKUP_POINTER" 2>/dev/null || true)"
    [ -f "$RESTORE" ] || { echo "Nadjen je stari izmenjeni Material, a nema rezervne kopije za vracanje."; exit 1; }
fi

trap 'echo "GREŠKA: instalacija nije završena. Vraćanje: sudo bash $STAGE/uninstall.sh"' ERR
systemctl stop lyrionmusicserver
if [ -n "$RESTORE" ]; then
    rm -rf "$MATERIAL"
    tar xzf "$RESTORE" -C "$PLUGINS"
    chown -R squeezeboxserver:nogroup "$MATERIAL"
    echo "Vraćen originalni Material Skin iz $RESTORE"
fi
mkdir -p "$UNIFIED_DIR"
rm -rf "$UNIFIED"
cp -r "$STAGE/UnifiedMusic" "$UNIFIED"
chown -R squeezeboxserver:nogroup "$UNIFIED"
find "$UNIFIED" -type d -exec chmod 755 {} +
find "$UNIFIED" -type f -exec chmod 644 {} +
systemctl start lyrionmusicserver
systemctl is-active lyrionmusicserver
echo "INSTALIRANO"
