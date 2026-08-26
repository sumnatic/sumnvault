[CmdletBinding()]
param(
  [ValidateSet('all', 'windows', 'linux', 'macos', 'android')]
  [string]$Target = 'all',
  [string]$Output = 'dist',
  [switch]$SkipAndroidBundle
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root $Output

function Invoke-Flutter([string[]]$Arguments) {
  Write-Host ("flutter " + ($Arguments -join ' ')) -ForegroundColor Cyan
  & flutter @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Flutter command failed: flutter $($Arguments -join ' ')" }
}

function New-Archive([string]$Source, [string]$Destination) {
  if (Test-Path $Destination) { Remove-Item $Destination -Force }
  Compress-Archive -Path $Source -DestinationPath $Destination -Force
}

Set-Location $root
New-Item -ItemType Directory -Path $out -Force | Out-Null
$checksums = Join-Path $out 'SHA256SUMS.txt'
if (Test-Path $checksums) { Remove-Item $checksums -Force }
Invoke-Flutter @('pub', 'get')
Invoke-Flutter @('analyze')
Invoke-Flutter @('test')

$targets = if ($Target -eq 'all') { @('windows', 'linux', 'macos', 'android') } else { @($Target) }
foreach ($platform in $targets) {
  switch ($platform) {
    'windows' {
      if ($IsLinux -or $IsMacOS) { throw 'Windows release must be built on Windows.' }
      Invoke-Flutter @('build', 'windows', '--release')
      $source = Join-Path $root 'build\windows\x64\runner\Release'
      New-Archive $source (Join-Path $out 'sumnvault-windows-x64.zip')
    }
    'linux' {
      if (-not $IsLinux) { throw 'Linux release must be built on Linux.' }
      Invoke-Flutter @('build', 'linux', '--release')
      $source = Join-Path $root 'build/linux/x64/release/bundle'
      New-Archive $source (Join-Path $out 'sumnvault-linux-x64.zip')
    }
    'macos' {
      if (-not $IsMacOS) { throw 'macOS release must be built on macOS with Xcode installed.' }
      Invoke-Flutter @('build', 'macos', '--release')
      $source = Join-Path $root 'build/macos/Build/Products/Release/sumnvault.app'
      New-Archive $source (Join-Path $out 'sumnvault-macos.zip')
    }
    'android' {
      Invoke-Flutter @('build', 'apk', '--release')
      Copy-Item (Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk') (Join-Path $out 'sumnvault-android-universal.apk') -Force
      if (-not $SkipAndroidBundle) {
        Invoke-Flutter @('build', 'appbundle', '--release')
        $aab = Join-Path $root 'build\app\outputs\bundle\release\app-release.aab'
        if (-not (Test-Path $aab)) { throw 'Android App Bundle was not produced.' }
        Copy-Item $aab (Join-Path $out 'sumnvault-android-release.aab') -Force
      }
    }
  }
}

Write-Host "Release artifacts written to $out" -ForegroundColor Green
Get-ChildItem $out -File | ForEach-Object {
  $hash = Get-FileHash $_.FullName -Algorithm SHA256
  "$($hash.Hash.ToLowerInvariant())  $($_.Name)" | Out-File $checksums -Append -Encoding ascii
}
Get-ChildItem $out -File | Select-Object Name, Length
