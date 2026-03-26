#Requires -Version 5.1
param(
    [switch]$Gui,
    [switch]$NoTests,
    [switch]$Debug,
    [switch]$Release,
    [switch]$Package,  # Bundle runtime DLLs + magic.mgc and produce a zip
    [switch]$Offline   # Also bundle portable tools (ffmpeg, soffice, pandoc, etc.)
                       # Implies -Package. Tools must be extracted under thirdparty/portable/
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Split-Path -Parent $ScriptDir
$BuildDir  = Join-Path $RootDir "build\windows"

# --- Parse flags -------------------------------------------------------------
$BuildGui   = if ($Gui)     { "ON"    } else { "OFF"     }
$BuildTests = if ($NoTests) { "OFF"   } else { "ON"      }
$BuildType  = if ($Debug)   { "Debug" } else { "Release" }

# -Offline implies -Package
if ($Offline) { $Package = $true }

Write-Host ""
Write-Host "+-- Build Config -------------------------------------------+"
Write-Host "|  Type    : $BuildType"
Write-Host "|  GUI     : $BuildGui"
Write-Host "|  Tests   : $BuildTests"
Write-Host "|  Package : $Package"
Write-Host "|  Offline : $Offline"
Write-Host "+-----------------------------------------------------------+"
Write-Host ""

# --- Configure ---------------------------------------------------------------
cmake -S $RootDir -B $BuildDir `
    -DCMAKE_BUILD_TYPE="$BuildType" `
    -DBUILD_GUI="$BuildGui" `
    -DBUILD_TESTS="$BuildTests"

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# --- Build -------------------------------------------------------------------
cmake --build $BuildDir --config $BuildType --parallel $env:NUMBER_OF_PROCESSORS

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Build complete -> $BuildDir\bin\"

# --- Helper used by offline bundling -----------------------------------------
function Copy-Tool {
    param([string]$Label, [string]$Src, [string]$Dst)
    if (Test-Path $Src) {
        Write-Host "  [$Label] $Src"
        New-Item -ItemType Directory -Path $Dst -Force | Out-Null
        Copy-Item "$Src\*" $Dst -Recurse -Force
    } else {
        Write-Warning "  [$Label] NOT FOUND at $Src - skipped"
    }
}

# --- Package -----------------------------------------------------------------
if (-not $Package) { exit 0 }

Write-Host ""
Write-Host "Packaging..."

$BinDir   = Join-Path $BuildDir "bin"
$DistDir  = Join-Path $BuildDir "dist\everyfile"
$ZipPath  = Join-Path $BuildDir "dist\everyfile-windows.zip"

# Find MSYS2 mingw64
$Msys2Roots = @("C:\msys64", "D:\msys64", "$env:USERPROFILE\msys64")
$MingwBin   = $null
foreach ($r in $Msys2Roots) {
    $candidate = Join-Path $r "mingw64\bin"
    if (Test-Path $candidate) { $MingwBin = $candidate; break }
}
if (-not $MingwBin) {
    Write-Error "Could not find MSYS2 mingw64/bin. Install MSYS2 to C:\msys64 or set MingwBin manually."
    exit 1
}
$Msys2Root = Split-Path (Split-Path $MingwBin)

Write-Host "  MSYS2 mingw64/bin : $MingwBin"

# Recreate dist folder
if (Test-Path $DistDir) { Remove-Item $DistDir -Recurse -Force }
New-Item -ItemType Directory -Path $DistDir | Out-Null

# Copy everything from bin/ (Qt DLLs, QML modules, plugins, our exes)
Write-Host "  Copying build output..."
Copy-Item "$BinDir\*" $DistDir -Recurse

# MSYS2 runtime DLLs required at runtime
$RuntimeDlls = @(
    "libgcc_s_seh-1.dll",
    "libstdc++-6.dll",
    "libwinpthread-1.dll",
    "libbz2-1.dll",
    "libzstd.dll",
    "liblzma-5.dll",
    "zlib1.dll",
    "libcrypto-3-x64.dll",
    "libiconv-2.dll",
    "libintl-8.dll",
    "libexpat-1.dll",
    "libtre-5.dll",
    "libsystre-0.dll",
    "libb2-1.dll",
    "liblz4.dll",
    "libminizip-1.dll",
    "libarchive-13.dll",
    "libassimp-6.dll",
    "libmagic-1.dll",
    "libpcre2-8-0.dll",
    "libpcre2-16-0.dll",
    "libdouble-conversion.dll",
    "libfreetype-6.dll",
    "libglib-2.0-0.dll",
    "libgraphite2.dll",
    "libharfbuzz-0.dll",
    "libicudt78.dll",
    "libicuin78.dll",
    "libicuuc78.dll",
    "libmd4c.dll",
    "libpng16-16.dll",
    "libbrotlicommon.dll",
    "libbrotlidec.dll"
)

Write-Host "  Copying runtime DLLs..."
$missing = @()
foreach ($dll in $RuntimeDlls) {
    $src = Join-Path $MingwBin $dll
    if (Test-Path $src) {
        Copy-Item $src $DistDir
    } else {
        $missing += $dll
    }
}
if ($missing.Count -gt 0) {
    Write-Warning "The following DLLs were not found and were skipped: $($missing -join ', ')"
}

# magic.mgc - libmagic file-type database
$MagicMgc = Join-Path $Msys2Root "mingw64\share\misc\magic.mgc"
if (Test-Path $MagicMgc) {
    Write-Host "  Copying magic.mgc..."
    Copy-Item $MagicMgc $DistDir
} else {
    Write-Warning "magic.mgc not found at $MagicMgc - file-type detection may fall back to extension only"
}

# Launcher batch file that sets MAGIC env var so libmagic finds magic.mgc
$LauncherContent = @'
@echo off
set MAGIC=%~dp0magic.mgc
start "" "%~dp0anyfile_gui.exe" %*
'@
Set-Content -Path (Join-Path $DistDir "everyfile.bat") -Value $LauncherContent -Encoding ASCII

# Remove test binary from the distribution
$testExe = Join-Path $DistDir "anyfile_tests.exe"
if (Test-Path $testExe) { Remove-Item $testExe }

# --- Offline: bundle portable tools into dist/tools/ -------------------------
if ($Offline) {
    Write-Host ""
    Write-Host "Bundling portable tools..."

    $PortableDir = Join-Path $RootDir "thirdparty\portable"
    $ToolsDir    = Join-Path $DistDir "tools"

    # FFmpeg — thirdparty/portable/ffmpeg/  →  tools/ffmpeg/
    Copy-Tool "ffmpeg"      (Join-Path $PortableDir "ffmpeg")                                        (Join-Path $ToolsDir "ffmpeg")

    # Pandoc — thirdparty/portable/pandoc/  →  tools/pandoc/
    Copy-Tool "pandoc"      (Join-Path $PortableDir "pandoc")                                        (Join-Path $ToolsDir "pandoc")

    # Poppler — thirdparty/portable/poppler/Library/bin/  →  tools/poppler/bin/
    Copy-Tool "poppler"     (Join-Path $PortableDir "poppler\Library\bin")                           (Join-Path $ToolsDir "poppler\bin")

    # Calibre — thirdparty/portable/calibre/Calibre/  →  tools/calibre/
    Copy-Tool "calibre"     (Join-Path $PortableDir "calibre\Calibre")                              (Join-Path $ToolsDir "calibre")

    # LibreOffice — thirdparty/portable/libreoffice/.../program/  →  tools/libreoffice/program/
    $LoProgramSrc = Join-Path $PortableDir "libreoffice\LibreOfficePortablePrevious\App\libreoffice\program"
    Copy-Tool "libreoffice" $LoProgramSrc                                                            (Join-Path $ToolsDir "libreoffice\program")

    Write-Host "  Tools bundled -> $ToolsDir"
}

# --- Compress ----------------------------------------------------------------
Write-Host ""
$distParent = Split-Path $ZipPath
if (-not (Test-Path $distParent)) { New-Item -ItemType Directory -Path $distParent | Out-Null }

# Prefer 7-Zip (much better compression), fall back to Compress-Archive
$SevenZip = $null
foreach ($candidate in @("7z", "C:\Program Files\7-Zip\7z.exe", "C:\Program Files (x86)\7-Zip\7z.exe")) {
    if (Get-Command $candidate -ErrorAction SilentlyContinue) { $SevenZip = $candidate; break }
    if (Test-Path $candidate)                                  { $SevenZip = $candidate; break }
}

if ($SevenZip) {
    $ArchivePath = [System.IO.Path]::ChangeExtension($ZipPath, ".7z")
    Write-Host "  Creating 7z archive (this may take a while)..."
    if (Test-Path $ArchivePath) { Remove-Item $ArchivePath }
    & $SevenZip a -t7z -mx=9 -mmt=on $ArchivePath $DistDir | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Error "7z failed"; exit 1 }
    $FinalArchive = $ArchivePath
} else {
    Write-Warning "7-Zip not found, falling back to zip (install 7-Zip for better compression)"
    Write-Host "  Creating zip..."
    if (Test-Path $ZipPath) { Remove-Item $ZipPath }
    Compress-Archive -Path $DistDir -DestinationPath $ZipPath
    $FinalArchive = $ZipPath
}

Write-Host ""
Write-Host "+-- Package ready ------------------------------------------+"
Write-Host "|  Folder  : $DistDir"
Write-Host "|  Archive : $FinalArchive"
if ($Offline) {
Write-Host "|  Mode    : OFFLINE (tools bundled)"
} else {
Write-Host "|  Mode    : Online (tools must be in PATH)"
}
Write-Host "+-----------------------------------------------------------+"
Write-Host ""
