#!/usr/bin/env bash
# Instalira plugin Unified Music. Pokrece se kao root iz raspakovanog paketa:
#   sudo bash install.sh
# Plugin ide tamo gde ga stavlja i Lyrion (cache/InstalledPlugins) i upisuje se u Lyrion sa svojim
# repozitorijumom, pa ga Lyrion posle azurira sam, kao bilo koji drugi plugin; ova skripta je potrebna
# samo za prvu instalaciju. Lyrion stoji dok se menjaju plugin i podesavanja (reprodukcija se prekida).
set -euo pipefail

STAGE="$(cd "$(dirname "$0")" && pwd)"
PLUGINS=/var/lib/squeezeboxserver/cache/InstalledPlugins/Plugins
MATERIAL="$PLUGINS/MaterialSkin"
UNIFIED="$PLUGINS/UnifiedMusic"
# rucne instalacije do 1.2.6 (Lyrion ih ne azurira)
OLD_UNIFIED="/usr/share/squeezeboxserver/Plugins/UnifiedMusic /var/lib/squeezeboxserver/Plugins/UnifiedMusic"
EXT_PREFS=/var/lib/squeezeboxserver/prefs/plugin/extensions.prefs
REPO_URL=https://nas963.github.io/lyrion-unified-music/repo.xml
OLD_BACKUP_POINTER=/var/lib/squeezeboxserver/backup-f1-latest

[ "$(id -u)" -eq 0 ] || { echo "Pokreni kao root: sudo bash install.sh"; exit 1; }
command -v systemctl >/dev/null || { echo "Paket je za Debian/Ubuntu sa systemd-om."; exit 1; }
systemctl cat lyrionmusicserver >/dev/null 2>&1 || { echo "Nije nadjen servis lyrionmusicserver."; exit 1; }
[ -f "$STAGE/UnifiedMusic/install.xml" ] || { echo "Nema plugina u $STAGE"; exit 1; }
[ -d "$MATERIAL" ] || { echo "Prvo instaliraj Material Skin iz Lyrion podesavanja."; exit 1; }
command -v python3 >/dev/null || { echo "Potreban je python3."; exit 1; }

RESTORE=""
if grep -q '<version>900\.' "$MATERIAL/install.xml"; then
    RESTORE="$(cat "$OLD_BACKUP_POINTER" 2>/dev/null || true)"
    [ -f "$RESTORE" ] || { echo "Nadjen je stari izmenjeni Material, a nema rezervne kopije za vracanje."; exit 1; }
fi

trap 'echo "GREŠKA: instalacija nije završena. Vraćanje: curl -fsSL https://github.com/nas963/lyrion-unified-music/releases/latest/download/get.sh | sudo bash -s uninstall"; systemctl start lyrionmusicserver || true' ERR
systemctl stop lyrionmusicserver
if [ -n "$RESTORE" ]; then
    rm -rf "$MATERIAL"
    tar xzf "$RESTORE" -C "$PLUGINS"
    chown -R squeezeboxserver:nogroup "$MATERIAL"
    echo "Vraćen originalni Material Skin iz $RESTORE"
fi
for old in $OLD_UNIFIED; do rm -rf "$old"; done
rm -rf "$UNIFIED"
cp -r "$STAGE/UnifiedMusic" "$UNIFIED"
chown -R squeezeboxserver:nogroup "$UNIFIED"
find "$UNIFIED" -type d -exec chmod 755 {} +
find "$UNIFIED" -type f -exec chmod 644 {} +
install -d -o squeezeboxserver -g nogroup -m 755 "$(dirname "$EXT_PREFS")"
python3 "$STAGE/lms-repo.py" add "$EXT_PREFS" UnifiedMusic "$REPO_URL"
chown squeezeboxserver:nogroup "$EXT_PREFS"
echo "Plugin je u $UNIFIED; azurira ga Lyrion (repozitorijum $REPO_URL)."
systemctl start lyrionmusicserver
systemctl is-active lyrionmusicserver
echo "INSTALIRANO"
