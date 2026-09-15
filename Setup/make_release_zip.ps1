$ErrorActionPreference = 'Stop'

$packageName = 'SYNC_ScreenLayout'
$projectDir = Split-Path -Parent $PSScriptRoot
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
  },
  @{
    Source = Join-Path $projectDir 'CODEX_AUTOMATION.md'
    Destination = 'CODEX_AUTOMATION.md'
    Description = 'Codex operation guide and production knowledge'
  }
)

foreach ($item in $packageFiles) {
  if (-not (Test-Path -LiteralPath $item.Source -PathType Leaf)) {
    Write-Host "$($item.Description) not found:"
    Write-Host "  $($item.Source)"
    Write-Host 'Build Release and ensure CODEX_AUTOMATION.md exists in the project root, then run this batch again.'
    exit 1
  }
}

# Restrict recursive cleanup to the staging folder directly under Setup.
$expectedWorkDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $packageName))
if ([IO.Path]::GetFullPath($workDir) -ne $expectedWorkDir) {
  throw 'Unexpected package staging directory.'
}
if (Test-Path -LiteralPath $workDir) {
  $existingWorkDir = Get-Item -LiteralPath $workDir
  if ($existingWorkDir.FullName -ne $expectedWorkDir -or
      ($existingWorkDir.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'Package staging directory must be a regular directory under Setup.'
  }
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
