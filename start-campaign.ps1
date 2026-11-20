<#
  Starts a Project Reclaimer dedicated server running Halo 3 or Halo 3: ODST campaign co-op.
  Asks which mission to start on (or pass -Mission <number> to skip the menu).

  Difficulty, scaling, skulls, missions, ports and the other settings are in
  reclaimer.config.json (shared with the Docker image). See https://projectreclaimer.dev/host#campaign.

  First run copies the needed game files from your MCC install into the server folder.
#>
param(
    [string]$ServerDir = (Join-Path $PSScriptRoot 'campaign-server'),
    [int]$Port,
    [string]$Name,
    [string]$MccDir = $(if ($env:RECLAIMER_MCC_DIR) { $env:RECLAIMER_MCC_DIR }
                        else { 'D:\SteamLibrary\steamapps\common\Halo The Master Chief Collection' }),
    [int]$Mission
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
$cfg = Get-ReclaimerConfig
$camp = $cfg.campaign
if (-not $Port) { $Port = $camp.port }
if (-not $Name) { $Name = $camp.name }
$exe = Get-DedicatedExe
$missions = @($camp.missions)

if ($Mission) {
    $choice = $missions | Where-Object { $_.id -eq $Mission }
    if (-not $choice) { throw "Unknown mission number: $Mission" }
} else {
    $lastGame = $null
    for ($i = 0; $i -lt $missions.Count; $i++) {
        $m = $missions[$i]
        if ($m.game -ne $lastGame) { Write-Host "`n$(if ($m.game -eq 'odst') { 'ODST' } else { 'Halo 3' })"; $lastGame = $m.game }
        Write-Host ('  {0,2}. {1}' -f ($i + 1), $m.name)
    }
    do {
        $answer = Read-Host "`nStart on which mission? (1-$($missions.Count))"
        $n = 0
        $valid = [int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $missions.Count
    } until ($valid)
    $choice = $missions[$n - 1]
}
$odst = $choice.game -eq 'odst'
Write-Host "Starting $($choice.name) ($($choice.id))"

# One-time setup: copy the game's files from MCC (re-running init keeps existing settings).
if ($odst) { $marker = 'game\halo3odst\maps\shared.map'; $maps = 'odst' }
else       { $marker = 'game\halo3\halo3.dll';           $maps = 'campaign' }
if (-not (Test-Path (Join-Path $ServerDir $marker))) {
    & $exe dedicated init $ServerDir --from $MccDir --maps $maps
    if ($LASTEXITCODE -ne 0) { throw "dedicated init failed ($LASTEXITCODE)" }
}

$config = Join-Path $ServerDir 'dedicated.toml'
if ((Test-Path $config) -and -not (Test-Path "$config.bak")) { Copy-Item $config "$config.bak" }

$skulls = ($camp.skulls.PSObject.Properties.Value | Measure-Object -Sum).Sum
# ODST servers use an `odst` block and have no custom_characters setting.
if ($odst) { $section = 'odst'; $characters = '' }
else       { $section = 'campaign'; $characters = "custom_characters = $(Get-Toml $camp.custom_characters)" }

$toml = (Get-TomlHeader $cfg (Get-RconPassword $ServerDir)) + (Get-TomlServerCommon $cfg $Name $Port) + @"


[server.$section]
mission = $($choice.id)
insertion = $($camp.insertion)
difficulty = $(Get-Toml $camp.difficulty)
$characters

[server.$section.modifiers]
health_per_player_percent = $($camp.health_per_player_percent)
damage_per_player_percent = $($camp.damage_per_player_percent)
sprint = $(Get-Toml $camp.sprint)
skulls = $skulls
"@
Write-Utf8NoBom $config $toml

Write-LanIps $Port

Push-Location $ServerDir
try {
    & $exe dedicated check
    if ($LASTEXITCODE -ne 0) { throw "dedicated check failed ($LASTEXITCODE); see the lines it names above" }
    & $exe dedicated
} finally {
    Pop-Location
}
