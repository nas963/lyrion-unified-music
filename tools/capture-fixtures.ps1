# Snima stvarne odgovore servera u tests/fixtures. Samo citanje, bez promene stanja plejera.
param(
    [Parameter(Mandatory)][string]$Server,
    [Parameter(Mandatory)][string]$Player,
    [string]$Term = 'Kind of Blue',
    [int]$Limit = 20
)
$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot '..\tests\fixtures'
New-Item -ItemType Directory -Force $out | Out-Null

function Rpc([string]$player, [object[]]$cmd) {
    $body = @{ id = 1; method = 'slim.request'; params = @($player, $cmd) } | ConvertTo-Json -Depth 8 -Compress
    (Invoke-RestMethod -Uri $Server -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 60).result
}
function Save([string]$name, $result) {
    $result | ConvertTo-Json -Depth 30 | Set-Content -Encoding utf8NoBOM (Join-Path $out "$name.json")
}
function Open([string]$itemId, [int]$count) {
    Rpc $Player @('globalsearch', 'items', 0, $count, 'menu:1', "item_id:$itemId")
}
function Child($menu, [string]$text) {
    $found = $menu.item_loop | Where-Object text -eq $text
    if (-not $found) { throw "Nije nadjeno: $text" }
    $found.actions.go.params.item_id
}

$root = Rpc $Player @('globalsearch', 'items', 0, 30, 'menu:1', "search:$Term")
Save 'gs_root' $root

$services = @{
    qobuz = @{ name = 'Qobuz'; albums = 'Releases' }
    tidal = @{ name = 'TIDAL'; albums = 'Albums' }
}
foreach ($key in $services.Keys) {
    $svc = $services[$key]
    $menu = Open (Child $root $svc.name) 20
    Save "${key}_root" $menu
    Save "${key}_albums" (Open (Child $menu $svc.albums) $Limit)
    Save "${key}_tracks" (Open (Child $menu 'Songs') $Limit)
    Save "${key}_artists" (Open (Child $menu 'Artists') $Limit)
    Save "${key}_playlists" (Open (Child $menu 'Playlists') $Limit)
}

Save 'local_albums' (Rpc '' @('albums', 0, $Limit, "search:$Term", 'tags:aljyeS'))
Save 'local_tracks' (Rpc '' @('tracks', 0, $Limit, 'search:So What', 'tags:aelyoTIJu'))
Save 'local_artists' (Rpc '' @('artists', 0, $Limit, 'search:Miles Davis'))
Save 'local_works' (Rpc '' @('works', 0, $Limit, "search:$Term"))
Save 'local_playlists' (Rpc '' @('playlists', 0, $Limit, 'search:a'))
