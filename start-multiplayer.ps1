<#
  Starts a Project Reclaimer dedicated server running a Halo 3 multiplayer playlist that
  players vote on between games. The maps, modes, vote time and other settings are in
  reclaimer.config.json (shared with the Docker image).

  Uses the same server folder and game files as start-campaign.ps1 but its own config file
  (multiplayer.toml) and its own port, so both can run at once.
#>
param(
    [string]$ServerDir = (Join-Path $PSScriptRoot 'campaign-server'),
    [int]$Port,
    [string]$Name,
    [string]$MccDir = $(if ($env:RECLAIMER_MCC_DIR) { $env:RECLAIMER_MCC_DIR }
                        else { 'D:\SteamLibrary\steamapps\common\Halo The Master Chief Collection' }),
    [int]$VoteSeconds
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
$cfg = Get-ReclaimerConfig
$mp = $cfg.multiplayer
if (-not $Port) { $Port = $mp.port }
if (-not $Name) { $Name = $mp.name }
if (-not $VoteSeconds) { $VoteSeconds = $mp.vote_seconds }
$exe = Get-DedicatedExe

# One round per game: a new ballot opens only when a game ends, and several of these
# variants otherwise play more than one round.
$games = foreach ($map in $mp.maps) {
    foreach ($mode in $mp.modes) {
        [ordered]@{ map = $map.name; game = $mode.game; name = $mode.name; options = @{ 'rounds.limit' = $mp.rounds_limit } }
    }
}

# One-time setup: copy any missing maps from MCC (re-running init keeps existing settings).
$missing = $mp.maps.file | Where-Object { -not (Test-Path (Join-Path $ServerDir "game\halo3\maps\$_.map")) }
if ($missing) {
    & $exe dedicated init $ServerDir --from $MccDir --maps ($missing -join ',')
    if ($LASTEXITCODE -ne 0) { throw "dedicated init failed ($LASTEXITCODE)" }
}

$playlist = [ordered]@{ version = 2; name = $Name; vote_seconds = $VoteSeconds; games = $games }
New-Item -ItemType Directory -Force (Join-Path $ServerDir 'playlists') | Out-Null
Write-Utf8NoBom (Join-Path $ServerDir 'playlists\lan-multiplayer.playlist.json') ($playlist | ConvertTo-Json -Depth 4)

$toml = (Get-TomlHeader $cfg (Get-RconPassword $ServerDir)) + (Get-TomlServerCommon $cfg $Name $Port) + @"

playlist = "playlists/lan-multiplayer.playlist.json"
"@
$config = 'multiplayer.toml'
Write-Utf8NoBom (Join-Path $ServerDir $config) $toml

Write-LanIps $Port

Push-Location $ServerDir
try {
    & $exe dedicated --config $config check
    if ($LASTEXITCODE -ne 0) { throw "dedicated check failed ($LASTEXITCODE); see the lines it names above" }
    & $exe dedicated --config $config
} finally {
    Pop-Location
}
