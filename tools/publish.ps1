# Publish the current build to the live place through Open Cloud (Place Publishing API).
# The key lives in the user's environment variable ROBLOX_OPEN_CLOUD_KEY (never in the repo):
#   API system "universe-places", operation "write", experience «Последняя роща».
# Usage: powershell -NoProfile -File tools/publish.ps1 [-Saved]   (-Saved: save a version without publishing)
param([switch]$Saved)
$ErrorActionPreference = 'Stop'

$UniverseId = 10773149549
$PlaceId = 116200213474049
$Root = Split-Path -Parent $PSScriptRoot
$Place = Join-Path $Root 'build/SWARMFALL.rbxlx'

$Key = $env:ROBLOX_OPEN_CLOUD_KEY
if (-not $Key) { $Key = [Environment]::GetEnvironmentVariable('ROBLOX_OPEN_CLOUD_KEY', 'User') }
if (-not $Key) { throw 'ROBLOX_OPEN_CLOUD_KEY is not set (user environment variable)' }

Push-Location $Root
try {
	rojo build -o $Place
	if ($LASTEXITCODE -ne 0) { throw 'rojo build failed' }
} finally { Pop-Location }

$Type = if ($Saved) { 'Saved' } else { 'Published' }
$Uri = "https://apis.roblox.com/universes/v1/$UniverseId/places/$PlaceId/versions?versionType=$Type"
$Response = Invoke-RestMethod -Method Post -Uri $Uri -InFile $Place -ContentType 'application/xml' `
	-Headers @{ 'x-api-key' = $Key }
Write-Output ("{0}: place {1} version {2}" -f $Type, $PlaceId, $Response.versionNumber)
