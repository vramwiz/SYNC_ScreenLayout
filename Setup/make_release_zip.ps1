$ErrorActionPreference = 'Stop'

$packageName = 'SYNC_ScreenLayout'
$pluginDir = 'C:\ProgramData\aviutl2\Plugin\SYNC_ScreenLayout'
$workDir = Join-Path $PSScriptRoot $packageName
$zipFile = Join-Path $PSScriptRoot "$packageName.zip"

$packageFiles = @(
  @{
    Source = Join-Path $pluginDir 'SYNC_ScreenLayout_Filter.auf2'
    Destination = 'SYNC_ScreenLayout_Filter.auf2'
    Description = 'filter plugin'
  },
  @{
    Source = Join-Path $pluginDir 'sk4d.dll'
    Destination = 'sk4d.dll'
    Description = 'Skia runtime'
  }
)

foreach ($item in $packageFiles) {
  if (-not (Test-Path -LiteralPath $item.Source -PathType Leaf)) {
    Write-Host "$($item.Description) not found:"
    Write-Host "  $($item.Source)"
    Write-Host 'Build the Release configuration first, then run this batch again.'
    exit 1
  }
}

if (Test-Path -LiteralPath $workDir) {
  Remove-Item -LiteralPath $workDir -Recurse -Force
}

if (Test-Path -LiteralPath $zipFile) {
  Remove-Item -LiteralPath $zipFile -Force
}

try {
  New-Item -ItemType Directory -Path $workDir -Force | Out-Null

  foreach ($item in $packageFiles) {
    $destination = Join-Path $workDir $item.Destination
    $destinationDir = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $destinationDir)) {
      New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $item.Source -Destination $destination -Force
  }

  Compress-Archive -Path $workDir -DestinationPath $zipFile -Force
}
finally {
  if (Test-Path -LiteralPath $workDir) {
    Remove-Item -LiteralPath $workDir -Recurse -Force
  }
}

Write-Host 'Created:'
Write-Host "  $zipFile"
