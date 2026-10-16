#Requires -Version 5.1
<#
  Cobblemon client installer - Minecraft 1.21.1 (Fabric)

  Reads mods.json, downloads each pinned file from the official Modrinth CDN,
  verifies its SHA-512 (and size) against the manifest, and only then places it
  into your .minecraft\mods (or .minecraft\shaderpacks).

  Usage:
    .\install.ps1                 install everything into %APPDATA%\.minecraft
    .\install.ps1 -Minimal        only Cobblemon + Fabric API (no Sodium/Iris/shaders)
    .\install.ps1 -Force          re-download even if the file is already correct
    .\install.ps1 -Clean          also delete superseded jars (prevents duplicate-mod crashes)
    .\install.ps1 -GameDir D:\mc  install into another launcher's game folder
#>
[CmdletBinding()]
param(
    [string] $GameDir,
    [switch] $Minimal,
    [switch] $Force,
    [switch] $Clean
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

$scriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$manifestPath = Join-Path $scriptDir 'mods.json'

function Write-Step { param([string]$Text) Write-Host "[*] $Text" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Text) Write-Host "    $Text" -ForegroundColor Green }
function Write-Warn2{ param([string]$Text) Write-Host "    $Text" -ForegroundColor Yellow }

function Install-RemoteFile {
    param(
        [string] $Uri,
        [string] $OutFile,
        [int64]  $ExpectedSize,
        [string] $ExpectedSha512,
        [string] $Label
    )
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("cbm-" + [guid]::NewGuid().ToString('N') + ".part")
    try {
        $ok = $false
        for ($i = 1; $i -le 3 -and -not $ok; $i++) {
            try {
                if ($i -gt 1) { Write-Warn2 "retrying ($i/3)..." }
                Invoke-WebRequest -Uri $Uri -OutFile $tmp -UseBasicParsing -TimeoutSec 900 `
                    -Headers @{ 'User-Agent' = 'cobblemon-client-installer/1.0' }
                $ok = $true
            } catch {
                if ($i -eq 3) { throw }
                Start-Sleep -Seconds (2 * $i)
            }
        }

        $size = (Get-Item $tmp).Length
        if ($size -ne $ExpectedSize) {
            throw "size mismatch for ${Label}: got $size bytes, expected $ExpectedSize"
        }
        $sum = (Get-FileHash $tmp -Algorithm SHA512).Hash.ToLower()
        if ($sum -ne $ExpectedSha512.ToLower()) {
            throw "SHA-512 mismatch for ${Label}`n      expected $ExpectedSha512`n      got      $sum"
        }

        Move-Item -Force $tmp $OutFile
        return $size
    }
    finally {
        if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }
}

if (-not (Test-Path $manifestPath)) { throw "mods.json not found next to this script ($scriptDir)." }
$manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

# ---------- where to install ----------
if (-not $GameDir) { $GameDir = Join-Path $env:APPDATA '.minecraft' }
if (-not (Test-Path $GameDir)) {
    Write-Warn2 "Game folder does not exist yet: $GameDir"
    Write-Warn2 "Run Minecraft once (with Fabric $($manifest.game)), then run this again."
    New-Item -ItemType Directory -Force -Path $GameDir | Out-Null
}
$GameDir = (Resolve-Path $GameDir).Path

Write-Host ""
Write-Host "  Cobblemon client installer" -ForegroundColor White
Write-Host "  Minecraft $($manifest.game) / $($manifest.loader)  ->  $GameDir" -ForegroundColor DarkGray
Write-Host ""

if (Get-Process -Name javaw -ErrorAction SilentlyContinue) {
    Write-Warn2 "Minecraft is running. New mods only load after a full restart, so close it before playing."
    Write-Host ""
}

$entries = $manifest.files
if ($Minimal) { $entries = $entries | Where-Object { $_.required } }

$results  = @()
$stale    = @()
$bytesGot = 0

foreach ($e in $entries) {
    $destDir = Join-Path $GameDir $e.folder
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    $target = Join-Path $destDir $e.filename

    Write-Step "$($e.name) $($e.version)  ($([math]::Round($e.size/1MB,1)) MB)"

    # is the exact right content already there?
    $needDownload = $true
    if ((Test-Path $target) -and -not $Force) {
        if ((Get-FileHash $target -Algorithm SHA512).Hash.ToLower() -eq $e.sha512.ToLower()) {
            Write-Ok "already installed and verified - skipped"
            $results += [pscustomobject]@{ Name = $e.name; Status = 'up to date'; File = $e.filename }
            $needDownload = $false
        } else {
            Write-Warn2 "existing file has the wrong content - replacing it"
        }
    }

    if ($needDownload) {
        $bytesGot += Install-RemoteFile -Uri $e.url -OutFile $target -ExpectedSize $e.size `
                                       -ExpectedSha512 $e.sha512 -Label $e.filename
        Write-Ok "downloaded, SHA-512 verified, installed"
        $results += [pscustomobject]@{ Name = $e.name; Status = 'installed'; File = $e.filename }
    }

    # superseded jars sitting next to ours = the classic "two Cobblemon jars" crash
    $others = Get-ChildItem -Path $destDir -Filter $e.staleGlob -File -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -ne $e.filename }
    foreach ($o in $others) {
        if ($Clean) {
            Remove-Item $o.FullName -Force
            Write-Warn2 "removed superseded $($o.Name)"
            $results += [pscustomobject]@{ Name = $e.name; Status = 'deleted old'; File = $o.Name }
        } else {
            $stale += "$($o.FullName)"
            $results += [pscustomobject]@{ Name = $e.name; Status = 'OLD - left alone'; File = $o.Name }
        }
    }
}

# ---------- summary ----------
Write-Host ""
Write-Host "  Summary" -ForegroundColor White
$results | Format-Table -AutoSize | Out-String | Write-Host

if ($bytesGot -gt 0) { Write-Host ("  downloaded $([math]::Round($bytesGot/1MB,1)) MB") -ForegroundColor DarkGray }

if ($stale.Count -gt 0) {
    Write-Host ""
    Write-Host "  WARNING: older versions are still in place:" -ForegroundColor Yellow
    $stale | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
    Write-Host "  Two versions of the same mod crash Minecraft on startup." -ForegroundColor Yellow
    Write-Host "  Re-run with:  .\install.ps1 -Clean" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Next steps" -ForegroundColor White
Write-Host "    1. Launch Minecraft with the Fabric $($manifest.game) profile (Java 21 required)."
if (-not $Minimal) {
    Write-Host "    2. Shaders: Options -> Video Settings -> Shader Packs -> pick Complementary Reimagined -> Apply."
    Write-Host "       (That menu only exists after a full restart, because Sodium/Iris load at startup.)"
}
Write-Host ""
Write-Host "  Done." -ForegroundColor Green
