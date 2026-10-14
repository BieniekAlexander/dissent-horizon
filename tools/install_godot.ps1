# Windows counterpart of tools/install_godot.sh: installs the Godot editor this project targets
# and puts a `godot` command (the console build, so headless runs print to the terminal) on the
# user PATH. No administrator rights needed.
#
#   powershell -ExecutionPolicy Bypass -File tools\install_godot.ps1
#
# Which version: as in install_godot.sh — project.godot's `config/features` major.minor, or the
# patch release pinned by an optional one-line `.godot-version` at the repo root.
#
# Idempotent: exits at once when `godot` already reports the wanted version.
# Env: GODOT_INSTALL_ROOT (default %LOCALAPPDATA%\Godot) holds one directory per version, plus
#      bin\godot.cmd, the shim pointed at the active one.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Root = Split-Path -Parent $PSScriptRoot
$InstallRoot = if ($env:GODOT_INSTALL_ROOT) { $env:GODOT_INSTALL_ROOT } else { Join-Path $env:LOCALAPPDATA 'Godot' }
$Releases = 'https://github.com/godotengine/godot-builds/releases/download'

$featuresLine = Select-String -Path (Join-Path $Root 'project.godot') -Pattern '^config/features=PackedStringArray\("([0-9]+\.[0-9]+)"' | Select-Object -First 1
if (-not $featuresLine) {
  Write-Error 'install_godot: no engine version in project.godot config/features'
}
$featuresVersion = $featuresLine.Matches[0].Groups[1].Value

$tag = "$featuresVersion-stable"
$pinFile = Join-Path $Root '.godot-version'
if (Test-Path $pinFile) {
  $tag = (Get-Content $pinFile -Raw).Trim()
  if (-not ($tag.StartsWith("$featuresVersion-") -or $tag.StartsWith("$featuresVersion."))) {
    Write-Error "install_godot: .godot-version ($tag) disagrees with project.godot ($featuresVersion)"
  }
}

# `godot --version` prints e.g. "4.7.stable.official.<hash>" for tag "4.7-stable".
$expectedPrefix = ($tag -replace '-', '.') + '.'
$existing = Get-Command godot -ErrorAction SilentlyContinue
if ($existing) {
  $current = (& godot --version 2>$null | Select-Object -First 1)
  if ($current -and $current.StartsWith($expectedPrefix)) {
    Write-Host "install_godot: Godot $tag already installed"
    exit 0
  }
}

$asset = "Godot_v${tag}_win64.exe"
$dest = Join-Path $InstallRoot $tag
$consoleExe = Join-Path $dest "Godot_v${tag}_win64_console.exe"
if (-not (Test-Path $consoleExe)) {
  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("godot-" + [guid]::NewGuid())
  New-Item -ItemType Directory -Force $tmp | Out-Null
  try {
    Write-Host "install_godot: downloading Godot $tag"
    Invoke-WebRequest -UseBasicParsing -Uri "$Releases/$tag/$asset.zip" -OutFile (Join-Path $tmp "$asset.zip")
    Invoke-WebRequest -UseBasicParsing -Uri "$Releases/$tag/SHA512-SUMS.txt" -OutFile (Join-Path $tmp 'SHA512-SUMS.txt')
    $expectedSum = $null
    foreach ($line in Get-Content (Join-Path $tmp 'SHA512-SUMS.txt')) {
      $parts = $line -split '\s+'
      if ($parts.Count -ge 2 -and $parts[1] -eq "$asset.zip") { $expectedSum = $parts[0] }
    }
    $actualSum = (Get-FileHash -Algorithm SHA512 (Join-Path $tmp "$asset.zip")).Hash
    if (-not $expectedSum -or $expectedSum -ne $actualSum.ToLower()) {
      Write-Error "install_godot: checksum mismatch for $asset.zip"
    }
    New-Item -ItemType Directory -Force $dest | Out-Null
    Expand-Archive -Force -Path (Join-Path $tmp "$asset.zip") -DestinationPath $dest
  } finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }
}

# A .cmd shim rather than a symlink: creating symlinks on Windows needs Developer Mode or admin.
$binDir = Join-Path $InstallRoot 'bin'
New-Item -ItemType Directory -Force $binDir | Out-Null
Set-Content -Encoding ascii -Path (Join-Path $binDir 'godot.cmd') -Value "@`"$consoleExe`" %*"

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$entries = @()
if ($userPath) { $entries = $userPath -split ';' | Where-Object { $_ } }
if ($entries -notcontains $binDir) {
  [Environment]::SetEnvironmentVariable('Path', (($entries + $binDir) -join ';'), 'User')
  Write-Host "install_godot: added $binDir to the user PATH (open a new terminal to pick it up)"
}
if (($env:Path -split ';') -notcontains $binDir) { $env:Path = "$binDir;$env:Path" }

Write-Host "install_godot: $(& $consoleExe --version) -> $(Join-Path $binDir 'godot.cmd')"
