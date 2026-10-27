# Grant the live experience permission to use every asset the code references (DD-101).
# A private image works in an experience only with a "Use" grant; publishing from Studio grants the
# assets the place file holds, but textures set from scripts (Shared.Art, the xenite icon...) were never
# granted: a phone showed 80 of 101 environment textures as Failure while every mesh loaded.
# Needs the Open Cloud key in the user env var ROBLOX_OPEN_CLOUD_KEY with API system
# "asset-permissions" (write). Assets not owned by the key's owner come back as per-asset errors.
# Usage: powershell -NoProfile -File tools/grant_assets.ps1
$ErrorActionPreference = 'Stop'

$UniverseId = '10773149549'
$Root = Split-Path -Parent $PSScriptRoot

$Key = $env:ROBLOX_OPEN_CLOUD_KEY
if (-not $Key) { $Key = [Environment]::GetEnvironmentVariable('ROBLOX_OPEN_CLOUD_KEY', 'User') }
if (-not $Key) { throw 'ROBLOX_OPEN_CLOUD_KEY is not set (user environment variable)' }

# every rbxassetid in the sources, plus the bare ids of Shared.Art's creature and machine rows
$ids = New-Object System.Collections.Generic.HashSet[string]
Get-ChildItem -Path (Join-Path $Root 'src') -Recurse -Filter *.luau | ForEach-Object {
	$text = Get-Content -Raw -Encoding UTF8 $_.FullName
	foreach ($m in [regex]::Matches($text, 'rbxassetid://(\d+)')) { [void]$ids.Add($m.Groups[1].Value) }
	if ($_.Name -eq 'Art.luau') {
		foreach ($m in [regex]::Matches($text, '"(\d{9,})"')) { [void]$ids.Add($m.Groups[1].Value) }
	}
}
$all = @($ids)
Write-Output ("{0} asset ids referenced" -f $all.Count)

$granted = 0
$failed = @{}
for ($i = 0; $i -lt $all.Count; $i += 50) {
	$chunk = $all[$i..([Math]::Min($i + 49, $all.Count - 1))]
	$requests = @($chunk | ForEach-Object { @{ assetId = [int64]$_; grantToDependencies = $true } })
	$body = @{
		subjectType = 'Universe'
		subjectId = $UniverseId
		action = 'Use'
		enableDeepAccessCheck = $true
		requests = $requests
	} | ConvertTo-Json -Depth 5
	$r = Invoke-RestMethod -Method Patch -Uri 'https://apis.roblox.com/asset-permissions-api/v1/assets/permissions' `
		-Headers @{ 'x-api-key' = $Key } -ContentType 'application/json' -Body $body
	$granted += @($r.successAssetIds).Count
	foreach ($e in @($r.errors)) {
		if ($e) {
			$code = [string]$e.code
			if (-not $failed.ContainsKey($code)) { $failed[$code] = 0 }
			$failed[$code] += 1
		}
	}
}
Write-Output ("granted: {0}" -f $granted)
foreach ($k in $failed.Keys) { Write-Output ("not granted ({0}): {1}" -f $k, $failed[$k]) }
