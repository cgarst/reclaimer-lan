# Helpers shared by start-campaign.ps1 and start-multiplayer.ps1.
# Tunable settings live in reclaimer.config.json (shared with the Docker image), not here.

function Get-ReclaimerConfig {
    Get-Content (Join-Path $PSScriptRoot 'config\reclaimer.config.json') -Raw | ConvertFrom-Json
}

# Newest dedicated server in this folder (update-binaries.ps1 downloads it).
function Get-DedicatedExe {
    $exe = Get-ChildItem $PSScriptRoot -Filter 'project-reclaimer-dedicated-v*.exe' |
        Sort-Object { [version]($_.Name -replace '^.*-v([\d.]+)\.exe$', '$1') } |
        Select-Object -Last 1 -ExpandProperty FullName
    if (-not $exe) { throw "No project-reclaimer-dedicated-v*.exe in $PSScriptRoot; run update-binaries.ps1" }
    $exe
}

# RCON is off without a password; make one on first run (start-rcon.ps1 reads it too).
function Get-RconPassword([string]$ServerDir) {
    $file = Join-Path $ServerDir 'rcon-password.txt'
    if (-not (Test-Path $file)) {
        $chars = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
        $bytes = New-Object byte[] 24
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
        [IO.File]::WriteAllText($file, (-join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })))
    }
    (Get-Content $file -Raw).Trim()
}

function Get-Toml([object]$Value) {
    if ($Value -is [bool]) { return "$Value".ToLower() }
    if ($Value -is [string]) { return '"' + ($Value -replace '\\', '\\' -replace '"', '\"') + '"' }
    "$Value"
}

# The TOML both start scripts share: general settings, [rcon] and the settings every [[server]] has.
function Get-TomlHeader([object]$Cfg, [string]$RconPassword) {
    @"
game = "game"
content = "content"
upnp = $(Get-Toml $Cfg.server.upnp)

# Remote console on TCP at the game port, reachable from this PC only.
[rcon]
password = $(Get-Toml $RconPassword)
address = "127.0.0.1"

"@
}

function Get-TomlServerCommon([object]$Cfg, [string]$Name, [int]$Port) {
    @"
[[server]]
name = $(Get-Toml $Name)
port = $Port
max_players = $($Cfg.server.max_players)
hidden = $(Get-Toml $Cfg.server.hidden)
friendly_fire = $(Get-Toml $Cfg.server.friendly_fire)
voice = $(Get-Toml $Cfg.server.voice)
"@
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    # Windows PowerShell's -Encoding utf8 adds a BOM, which TOML parsers may reject.
    [IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}

function Write-LanIps([int]$Port) {
    Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp, Manual -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '169.254.*' } |
        ForEach-Object { Write-Host "LAN players: Direct Connect to $($_.IPAddress):$Port" }
}
