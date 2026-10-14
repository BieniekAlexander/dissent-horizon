# PowerShell entry point for tools/build_native.sh, which holds the build itself: runs it with
# the bash that ships with Git for Windows. Arguments pass through (`--release`).
#
#   powershell -ExecutionPolicy Bypass -File tools\build_native.ps1 [--release]
#
# Needs MSVC (Visual Studio 2022 or its Build Tools, "Desktop development with C++") and SCons
# (`python -m pip install scons`). SCons finds MSVC itself, so no Developer Prompt is needed.
$ErrorActionPreference = 'Stop'

# Git's own bash, found from git rather than PATH: a bare `bash` on Windows is often WSL's,
# which cannot see the Windows Python, SCons or MSVC the build needs.
$gitRoot = (git --exec-path) -replace '[\\/]mingw64[\\/]libexec[\\/]git-core$', ''
$bash = Join-Path $gitRoot 'bin\bash.exe'
if (-not (Test-Path $bash)) {
  Write-Error "build_native: Git for Windows' bash not found at $bash"
}

& $bash (Join-Path $PSScriptRoot 'build_native.sh') @args
exit $LASTEXITCODE
