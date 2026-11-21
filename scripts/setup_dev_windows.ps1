# One-time setup of a Windows PC to work on Oganesson TakeNotes locally
# (with or without Claude Code).
#
# Installs, if missing: Git for Windows, Visual Studio 2022 Community with the
# "Desktop development with C++" workload, the Flutter SDK (stable) and
# Claude Code. Then clones the repository and prepares the Windows project.
#
# Usage (PowerShell, NOT as administrator):
#   Set-ExecutionPolicy -Scope Process Bypass
#   irm https://raw.githubusercontent.com/rafaeldb22/Oganesson-TakeNotes/main/scripts/setup_dev_windows.ps1 | iex
# or, from a downloaded copy:
#   powershell -ExecutionPolicy Bypass -File setup_dev_windows.ps1
#
# The repository is private: the clone step asks you to sign in to GitHub.

$ErrorActionPreference = 'Stop'
$develop = Join-Path $env:USERPROFILE 'develop'
$flutterDir = Join-Path $develop 'flutter'
$projectDir = Join-Path $develop 'Oganesson-TakeNotes'

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Have($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }
function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
              [Environment]::GetEnvironmentVariable('Path', 'User')
}

if (-not (Have winget)) {
  throw 'winget was not found. Install "App Installer" from the Microsoft Store and run this script again.'
}

New-Item -ItemType Directory -Force -Path $develop | Out-Null

# 1. Git for Windows (Flutter needs it; Claude Code uses Git Bash).
Step 'Git for Windows'
if (Have git) { Write-Host 'Already installed.' }
else {
  winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
  Refresh-Path
}

# 2. Visual Studio 2022 + C++ desktop workload (needed to build the Windows app).
#    VS 2022 specifically: MSVC 14.52 (VS 2026) cannot build the notifications plugin.
Step 'Visual Studio 2022 Community + "Desktop development with C++" (can take a while)'
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$hasVs = (Test-Path $vswhere) -and (& $vswhere -version '[17.0,18.0)' -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath)
if ($hasVs) { Write-Host 'Already installed.' }
else {
  winget install --id Microsoft.VisualStudio.2022.Community -e --source winget `
    --accept-package-agreements --accept-source-agreements `
    --override '--add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended --passive --norestart'
}

# 3. Flutter SDK (stable channel) in %USERPROFILE%\develop\flutter, added to the user PATH.
Step 'Flutter SDK (stable)'
if (Have flutter) { Write-Host 'Already installed.' }
else {
  if (-not (Test-Path $flutterDir)) {
    git clone https://github.com/flutter/flutter.git -b stable $flutterDir
  }
  $flutterBin = Join-Path $flutterDir 'bin'
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ($userPath -notlike "*$flutterBin*") {
    [Environment]::SetEnvironmentVariable('Path', "$flutterBin;$userPath", 'User')
  }
  Refresh-Path
}
flutter --version

# 4. Claude Code (official native installer, no admin needed).
Step 'Claude Code'
if (Have claude) { Write-Host 'Already installed.' }
else {
  Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression
  Refresh-Path
}

# 5. The project.
Step "Project in $projectDir"
if (-not (Test-Path $projectDir)) {
  git clone https://github.com/rafaeldb22/Oganesson-TakeNotes.git $projectDir
}
Set-Location $projectDir
./scripts/prepare_windows.ps1

Step 'Checking the toolchain'
flutter doctor

Write-Host "`nDone. Next:" -ForegroundColor Green
Write-Host "  cd `"$projectDir`""
Write-Host '  flutter run -d windows     # run the app'
Write-Host '  claude                     # start Claude Code in the project (first time: log in in the browser)'
Write-Host "`nIf 'flutter' or 'claude' are not recognised, close this window and open a new PowerShell."
