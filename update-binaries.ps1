<#
  Downloads the latest Project Reclaimer executables from GitHub releases into this folder:
    ProjectReclaimer/project-reclaimer-releases      client, dedicated server, customization editor, RCON client
    ProjectReclaimer/project-reclaimer-rcon-client   RCON client

  Each file is checked against the SHA-256 GitHub publishes for it. Files already here
  with a matching hash are skipped. Older versions are kept unless -RemoveOld is given.
  The start scripts use the newest version of each executable in this folder.
#>
param(
    [string]$Dir = $PSScriptRoot,
    [switch]$RemoveOld
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'  # Invoke-WebRequest is very slow with the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repos = 'ProjectReclaimer/project-reclaimer-releases', 'ProjectReclaimer/project-reclaimer-rcon-client'
$headers = @{ 'User-Agent' = 'reclaimer-scripts'; 'Accept' = 'application/vnd.github+json' }

# The same executable can be published in both repos; take each name once.
$assets = [ordered]@{}
foreach ($repo in $repos) {
    $release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers $headers
    Write-Host "$repo $($release.tag_name)"
    foreach ($asset in $release.assets | Where-Object { $_.name -like '*.exe' }) {
        if (-not $assets.Contains($asset.name)) { $assets[$asset.name] = $asset }
    }
}

foreach ($asset in $assets.Values) {
    if ($asset.digest -notmatch '^sha256:([0-9a-f]{64})$') { throw "No SHA-256 published for $($asset.name)" }
    $expected = $Matches[1]
    $target = Join-Path $Dir $asset.name

    if ((Test-Path $target) -and (Get-FileHash $target -Algorithm SHA256).Hash -eq $expected) {
        Write-Host "  up to date   $($asset.name)"
        continue
    }

    $partial = "$target.download"
    Invoke-WebRequest $asset.browser_download_url -OutFile $partial -Headers @{ 'User-Agent' = 'reclaimer-scripts' }
    $actual = (Get-FileHash $partial -Algorithm SHA256).Hash
    if ($actual -ne $expected) {
        Remove-Item $partial
        throw "SHA-256 mismatch for $($asset.name): expected $expected, got $($actual.ToLower())"
    }
    Move-Item $partial $target -Force
    Write-Host "  downloaded   $($asset.name)"

    if ($RemoveOld -and $asset.name -match '^(.+)-v[\d.]+\.exe$') {
        Get-ChildItem $Dir -Filter "$($Matches[1])-v*.exe" | Where-Object Name -ne $asset.name | ForEach-Object {
            Remove-Item $_.FullName
            Write-Host "  removed      $($_.Name)"
        }
    }
}
