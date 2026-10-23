<#
  Starts a Project Reclaimer dedicated server running Halo 3 or Halo 3: ODST campaign co-op.
  Asks which mission to start on (or pass -Mission <number> to skip the menu).

  Settings (per https://projectreclaimer.dev/host#campaign):
    Mission      Chosen at start, from the mission's beginning (insertion 0)
    Difficulty   Legendary
    Network      Online, but hidden (unlisted; players join by Direct Connect / address)
    Host         Friendly fire off, voice chat off
    Characters   Custom characters (Halo 3 only; ODST uses each player's trooper)
    Scaling      +25% enemy health and +25% enemy damage per extra player
    Sprint       On
    Skulls       Cowbell (2048) + Grunt Birthday Party (4096) + IWHBYD (8192) = 14336

  First run copies the needed game files from your MCC install into the server folder.
#>
param(
    [string]$ServerDir = (Join-Path $PSScriptRoot 'campaign-server'),
    [int]$Port = 12345,
    [string]$Name = 'Legendary Co-op',
    [string]$MccDir = $(if ($env:RECLAIMER_MCC_DIR) { $env:RECLAIMER_MCC_DIR }
                        else { 'D:\SteamLibrary\steamapps\common\Halo The Master Chief Collection' }),
    [int]$Mission
)

$ErrorActionPreference = 'Stop'

# Newest dedicated server in this folder (update-binaries.ps1 downloads it).
$exe = Get-ChildItem $PSScriptRoot -Filter 'project-reclaimer-dedicated-v*.exe' |
    Sort-Object { [version]($_.Name -replace '^.*-v([\d.]+)\.exe$', '$1') } |
    Select-Object -Last 1 -ExpandProperty FullName
if (-not $exe) { throw "No project-reclaimer-dedicated-v*.exe in $PSScriptRoot; run update-binaries.ps1" }

# Mission numbers from the docs (Halo 3) and `dedicated content odst` (ODST).
$missions = @(
    @{ Game = 'Halo 3'; Id = 3010; Name = 'Sierra 117' }
    @{ Game = 'Halo 3'; Id = 3020; Name = "Crow's Nest" }
    @{ Game = 'Halo 3'; Id = 3030; Name = 'Tsavo Highway' }
    @{ Game = 'Halo 3'; Id = 3040; Name = 'The Storm' }
    @{ Game = 'Halo 3'; Id = 3050; Name = 'Floodgate' }
    @{ Game = 'Halo 3'; Id = 3070; Name = 'The Ark' }
    @{ Game = 'Halo 3'; Id = 3100; Name = 'The Covenant' }
    @{ Game = 'Halo 3'; Id = 3110; Name = 'Cortana' }
    @{ Game = 'Halo 3'; Id = 3120; Name = 'Halo' }
    @{ Game = 'ODST';   Id = 4100; Name = 'Prepare to Drop' }
    @{ Game = 'ODST';   Id = 5000; Name = 'Mombasa Streets' }
    @{ Game = 'ODST';   Id = 6100; Name = 'Tayari Plaza' }
    @{ Game = 'ODST';   Id = 6110; Name = 'Uplift Reserve' }
    @{ Game = 'ODST';   Id = 6120; Name = 'Kizingo Boulevard' }
    @{ Game = 'ODST';   Id = 6130; Name = 'ONI Alpha Site' }
    @{ Game = 'ODST';   Id = 6140; Name = 'NMPD HQ' }
    @{ Game = 'ODST';   Id = 6150; Name = 'Kikowani Station' }
    @{ Game = 'ODST';   Id = 5200; Name = 'Data Hive' }
    @{ Game = 'ODST';   Id = 5300; Name = 'Coastal Highway' }
    @{ Game = 'ODST';   Id = 4200; Name = 'Epilogue' }
)

if ($Mission) {
    $choice = $missions | Where-Object { $_.Id -eq $Mission }
    if (-not $choice) { throw "Unknown mission number: $Mission" }
} else {
    $lastGame = $null
    for ($i = 0; $i -lt $missions.Count; $i++) {
        $m = $missions[$i]
        if ($m.Game -ne $lastGame) { Write-Host "`n$($m.Game)"; $lastGame = $m.Game }
        Write-Host ('  {0,2}. {1}' -f ($i + 1), $m.Name)
    }
    do {
        $answer = Read-Host "`nStart on which mission? (1-$($missions.Count))"
        $n = 0
        $valid = [int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $missions.Count
    } until ($valid)
    $choice = $missions[$n - 1]
}
$odst = $choice.Game -eq 'ODST'
Write-Host "Starting $($choice.Game): $($choice.Name) ($($choice.Id))"

# One-time setup: copy the game's files from MCC (re-running init keeps existing settings).
if ($odst) {
    $marker = 'game\halo3odst\maps\shared.map'; $maps = 'odst'
} else {
    $marker = 'game\halo3\halo3.dll'; $maps = 'campaign'
}
if (-not (Test-Path (Join-Path $ServerDir $marker))) {
    & $exe dedicated init $ServerDir --from $MccDir --maps $maps
    if ($LASTEXITCODE -ne 0) { throw "dedicated init failed ($LASTEXITCODE)" }
}

$config = Join-Path $ServerDir 'dedicated.toml'
if ((Test-Path $config) -and -not (Test-Path "$config.bak")) {
    Copy-Item $config "$config.bak"
}

# RCON is off without a password; make one on first run (start-rcon.ps1 reads it too).
$rconPasswordFile = Join-Path $ServerDir 'rcon-password.txt'
if (-not (Test-Path $rconPasswordFile)) {
    $chars = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $bytes = New-Object byte[] 24
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $generated = -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
    [IO.File]::WriteAllText($rconPasswordFile, $generated)
}
$rconPassword = (Get-Content $rconPasswordFile -Raw).Trim()

$skulls = 2048 + 4096 + 8192  # Cowbell + Grunt Birthday Party + IWHBYD

# ODST servers use an `odst` block and have no custom_characters setting.
if ($odst) {
    $section = 'odst'; $characters = ''
} else {
    $section = 'campaign'; $characters = 'custom_characters = true'
}

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

[server.$section]
mission = $($choice.Id)
insertion = 0
difficulty = "legendary"
$characters

[server.$section.modifiers]
health_per_player_percent = 25
damage_per_player_percent = 25
sprint = true
skulls = $skulls
"@
# Windows PowerShell's -Encoding utf8 adds a BOM, which TOML parsers may reject.
[IO.File]::WriteAllText($config, $toml, (New-Object System.Text.UTF8Encoding $false))

$lanIps = Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp, Manual -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike '169.254.*' } | ForEach-Object IPAddress
foreach ($ip in $lanIps) { Write-Host "LAN players: Direct Connect to ${ip}:$Port" }

Push-Location $ServerDir
try {
    & $exe dedicated check
    if ($LASTEXITCODE -ne 0) { throw "dedicated check failed ($LASTEXITCODE); see the lines it names above" }
    & $exe dedicated
} finally {
    Pop-Location
}
