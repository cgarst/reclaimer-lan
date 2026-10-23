<#
  Starts a Project Reclaimer dedicated server running a Halo 3 multiplayer playlist:
    Construct  One in the Chamber
    Guardian   Gun Game
    The Pit    Slayer

  Players vote between games in the lobby (the game just played sits out the next
  ballot), so with three games the server moves through all of them.
  Same LAN host settings as start-campaign.ps1: hidden, voice off, friendly fire off.

  Uses the same server folder and game files as start-campaign.ps1 but its own config
  file (multiplayer.toml), on the same port; stop the co-op server before starting this.
#>
param(
    [string]$ServerDir = (Join-Path $PSScriptRoot 'campaign-server'),
    [int]$Port = 49178,
    [string]$Name = 'LAN Multiplayer',
    [string]$MccDir = $(if ($env:RECLAIMER_MCC_DIR) { $env:RECLAIMER_MCC_DIR }
                        else { 'D:\SteamLibrary\steamapps\common\Halo The Master Chief Collection' }),
    [int]$VoteSeconds = 20
)

$ErrorActionPreference = 'Stop'

# Newest dedicated server in this folder (update-binaries.ps1 downloads it).
$exe = Get-ChildItem $PSScriptRoot -Filter 'project-reclaimer-dedicated-v*.exe' |
    Sort-Object { [version]($_.Name -replace '^.*-v([\d.]+)\.exe$', '$1') } |
    Select-Object -Last 1 -ExpandProperty FullName
if (-not $exe) { throw "No project-reclaimer-dedicated-v*.exe in $PSScriptRoot; run update-binaries.ps1" }

$games = @(
    @{ map = 'Construct'; game = 'One in the Chamber' }
    @{ map = 'Guardian';  game = 'Gun Game' }
    @{ map = 'The Pit';   game = 'Slayer' }
)

# One-time setup: copy the playlist's maps from MCC (re-running init keeps existing settings).
$mapFiles = @{ 'Construct' = 'construct'; 'Guardian' = 'guardian'; 'The Pit' = 'cyberdyne' }
$missing = $games | Where-Object {
    -not (Test-Path (Join-Path $ServerDir "game\halo3\maps\$($mapFiles[$_.map]).map"))
}
if ($missing) {
    & $exe dedicated init $ServerDir --from $MccDir --maps (($games | ForEach-Object { $_.map }) -join ',')
    if ($LASTEXITCODE -ne 0) { throw "dedicated init failed ($LASTEXITCODE)" }
}

$utf8 = New-Object System.Text.UTF8Encoding $false

$playlist = [ordered]@{
    version      = 2
    name         = $Name
    vote_seconds = $VoteSeconds
    games        = $games
}
$playlistFile = Join-Path $ServerDir 'playlists\lan-multiplayer.playlist.json'
[IO.File]::WriteAllText($playlistFile, ($playlist | ConvertTo-Json -Depth 4), $utf8)

# Shares start-campaign.ps1's RCON password, so start-rcon.ps1 works with either server.
$rconPasswordFile = Join-Path $ServerDir 'rcon-password.txt'
if (-not (Test-Path $rconPasswordFile)) {
    $chars = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $bytes = New-Object byte[] 24
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $generated = -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
    [IO.File]::WriteAllText($rconPasswordFile, $generated)
}
$rconPassword = (Get-Content $rconPasswordFile -Raw).Trim()

# LAN only: no port forwarding/UPnP. hidden = true keeps the server off the
# public masters; LAN players join by Direct Connect.
$toml = @"
game = "game"
content = "content"
upnp = false

# Remote console on TCP at the game port, reachable from this PC only.
[rcon]
password = "$rconPassword"
address = "127.0.0.1"

[[server]]
name = "$Name"
port = $Port
max_players = 16
hidden = true
friendly_fire = false
voice = false
playlist = "playlists/lan-multiplayer.playlist.json"
"@
$config = 'multiplayer.toml'
[IO.File]::WriteAllText((Join-Path $ServerDir $config), $toml, $utf8)

$lanIps = Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp, Manual -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike '169.254.*' } | ForEach-Object IPAddress
foreach ($ip in $lanIps) { Write-Host "LAN players: Direct Connect to ${ip}:$Port" }

Push-Location $ServerDir
try {
    & $exe dedicated --config $config check
    if ($LASTEXITCODE -ne 0) { throw "dedicated check failed ($LASTEXITCODE); see the lines it names above" }
    & $exe dedicated --config $config
} finally {
    Pop-Location
}
