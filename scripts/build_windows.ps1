#Requires -Version 5.1
param(
    [switch]$Gui,
    [switch]$Debug,
    [switch]$Release
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Split-Path -Parent $ScriptDir
$BuildDir  = Join-Path $RootDir "build\windows"

# ── Parse flags ──────────────────────────────────────────────────────────────
$BuildGui  = if ($Gui)   { "ON"      } else { "OFF"     }
$BuildType = if ($Debug) { "Debug"   } else { "Release" }

Write-Host ""
Write-Host "+-- Build Config -------------------------------------------+"
Write-Host "|  Type : $BuildType"
Write-Host "|  GUI  : $BuildGui"
Write-Host "+-----------------------------------------------------------+"
Write-Host ""

# ── Configure ────────────────────────────────────────────────────────────────
cmake -S $RootDir -B $BuildDir `
    -DCMAKE_BUILD_TYPE="$BuildType" `
    -DBUILD_GUI="$BuildGui"

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# ── Build ────────────────────────────────────────────────────────────────────
cmake --build $BuildDir --config $BuildType --parallel $env:NUMBER_OF_PROCESSORS

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Build complete -> $BuildDir\bin\"
