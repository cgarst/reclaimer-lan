<#
  Opens the Project Reclaimer RCON desktop client for the server started by start-campaign.ps1.

  The client takes no command-line arguments, so this copies the password to the
  clipboard and prints the Host and Port to enter. The server listens for RCON on
  TCP 127.0.0.1 at its game port (12345 by default).
#>
param(
    [string]$ServerDir = (Join-Path $PSScriptRoot 'campaign-server'),
    # Newest RCON client in this folder (update-binaries.ps1 downloads it).
    [string]$RconExe = (Get-ChildItem $PSScriptRoot -Filter 'reclaimer-rcon-v*.exe' |
        Sort-Object { [version]($_.Name -replace '^.*-v([\d.]+)\.exe$', '$1') } |
        Select-Object -Last 1 -ExpandProperty FullName)
)

$ErrorActionPreference = 'Stop'

if (-not $RconExe -or -not (Test-Path $RconExe)) { throw "RCON client not found; run update-binaries.ps1" }

$config = Join-Path $ServerDir 'dedicated.toml'
$rconPasswordFile = Join-Path $ServerDir 'rcon-password.txt'
if (-not (Test-Path $rconPasswordFile)) {
    throw "No RCON password yet; run start-campaign.ps1 first (it creates $rconPasswordFile)."
}
$password = (Get-Content $rconPasswordFile -Raw).Trim()

# RCON answers on the game port unless rcon_port overrides it.
$toml = Get-Content $config -Raw
$port = if ($toml -match '(?m)^rcon_port\s*=\s*(\d+)') { [int]$Matches[1] }
        elseif ($toml -match '(?m)^port\s*=\s*(\d+)') { [int]$Matches[1] }
        else { 12345 }

$client = New-Object Net.Sockets.TcpClient
try {
    $listening = $client.ConnectAsync('127.0.0.1', $port).Wait(1000)
} catch {
    $listening = $false
} finally {
    $client.Close()
}
if (-not $listening) {
    Write-Warning "Nothing is answering on 127.0.0.1:$port. Is the server running (start-campaign.ps1)?"
}

Set-Clipboard -Value $password
Write-Host "Host:     127.0.0.1"
Write-Host "Port:     $port"
Write-Host "Password: copied to the clipboard (also in $rconPasswordFile)"

Start-Process -FilePath $RconExe
