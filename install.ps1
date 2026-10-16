#Requires -Version 5.1
<#
  Cobblemon client installer - Minecraft 1.21.1 (Fabric)

  Works with the normal Minecraft launcher, TLauncher, Prism/MultiMC, the
  Modrinth App and CurseForge. It finds the right game folder, makes sure
  Fabric Loader is installed, then downloads every mod from its official
  source and verifies the SHA-512 before placing it.

  Xaero's Minimap is also moved to the top right corner, matching the modpack's own
  default and keeping the top left free for the F3 debug text.

  Usage:
    .\install.ps1                 auto-detect the game folder, install Fabric + mods
    .\install.ps1 -Minimal        only Cobblemon + Fabric API (no Sodium/Iris/shaders)
    .\install.ps1 -NoFabric       do not touch Fabric Loader
    .\install.ps1 -Force          re-download even if a file is already correct
    .\install.ps1 -Clean          delete superseded jars (prevents duplicate-mod crashes)
    .\install.ps1 -GameDir D:\mc  install into a specific game folder
    .\install.ps1 -KeepMinimapPosition  leave the minimap corner exactly as it is now
#>
[CmdletBinding()]
param(
    [string] $GameDir,
    [switch] $Minimal,
    [switch] $NoFabric,
    [switch] $Force,
    [switch] $Clean,
    [switch] $KeepMinimapPosition
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

$scriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$manifestPath = Join-Path $scriptDir 'mods.json'

function Write-Step { param([string]$Text) Write-Host "[*] $Text" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Text) Write-Host "    $Text" -ForegroundColor Green }
function Write-Warn2{ param([string]$Text) Write-Host "    $Text" -ForegroundColor Yellow }

# Get-FileHash only exists from PowerShell 4.0 up and needs a working module path.
# .NET's SHA-512 is present on every Windows install, so we use that instead.
function Get-Sha512Hex {
    param([string] $Path)
    $sha = [System.Security.Cryptography.SHA512]::Create()
    $fs  = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try     { $hash = $sha.ComputeHash($fs) }
    finally { $fs.Dispose(); $sha.Dispose() }
    return ([BitConverter]::ToString($hash) -replace '-', '').ToLower()
}

# Xaero's Minimap keeps the corner of each HUD module in <gamedir>\config\xaerohud.txt:
#   module;id=xaerominimap:minimap;x=0;y=0;centered=false;fromRight=false;fromBottom=false;...
# The game's own default is the top LEFT (fromRight=false), which collides with the F3
# debug text. We flip the minimap to the top RIGHT, the same corner the official Cobblemon
# modpack ships (x=0 = flush with that corner).
function Set-MinimapTopRight {
    param([string] $GameDir)

    $hud  = Join-Path $GameDir 'config\xaerohud.txt'
    $line = 'module;id=xaerominimap:minimap;x=0;y=0;centered=false;fromRight=true;fromBottom=false;flippedVer=false;flippedHor=false;'

    $dir = Split-Path $hud -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    if (-not (Test-Path $hud)) {
        Set-Content -Path $hud -Value $line -Encoding utf8
        return 'created'
    }

    $lines = [System.IO.File]::ReadAllLines($hud)
    $seen  = $false
    $out   = foreach ($l in $lines) {
        if ($l -match 'module;id=xaerominimap:minimap;') {
            $seen = $true
            ($l -replace 'x=-?\d+;', 'x=0;') -replace 'fromRight=(true|false);', 'fromRight=true;'
        } else { $l }
    }
    if (-not $seen) { $out = @($out) + $line }

    [System.IO.File]::WriteAllLines($hud, $out)
    return 'set'
}

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
                # .NET WebClient, not Invoke-WebRequest: streams straight to disk and does
                # not depend on which Microsoft.PowerShell.Utility module got autoloaded.
                $wc = New-Object System.Net.WebClient
                try {
                    $wc.Headers.Add('User-Agent', 'cobblemon-client-installer/1.0')
                    $wc.DownloadFile($Uri, $tmp)
                } finally { $wc.Dispose() }
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
        $sum = Get-Sha512Hex $tmp
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

# ---------- which game folder(s) are on this PC ----------
# Every launcher keeps its own .minecraft; these are the standard locations.
function Find-GameDirs {
    $found = @()
    $appdata = $env:APPDATA
    $found += [pscustomobject]@{ Path = (Join-Path $appdata '.minecraft'); Launcher = 'Minecraft launcher / TLauncher / most launchers' }
    $found += [pscustomobject]@{ Path = (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.4297127D64EC6_8wekyb3d8bbwe\LocalCache\Roaming\.minecraft'); Launcher = 'Minecraft launcher (Microsoft Store build)' }
    foreach ($b in @([pscustomobject]@{ Dir = (Join-Path $appdata 'PrismLauncher\instances'); What = 'Prism Launcher instance' },
                     [pscustomobject]@{ Dir = (Join-Path $appdata 'MultiMC\instances');      What = 'MultiMC instance' })) {
        Get-ChildItem $b.Dir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $found += [pscustomobject]@{ Path = (Join-Path $_.FullName '.minecraft'); Launcher = "$($b.What) '$($_.Name)'" }
        }
    }
    Get-ChildItem (Join-Path $appdata 'ModrinthApp\profiles') -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $found += [pscustomobject]@{ Path = $_.FullName; Launcher = "Modrinth App profile '$($_.Name)'" }
    }
    Get-ChildItem (Join-Path $env:USERPROFILE 'curseforge\minecraft\Instances') -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $found += [pscustomobject]@{ Path = $_.FullName; Launcher = "CurseForge instance '$($_.Name)'" }
    }
    return @($found | Where-Object { Test-Path $_.Path })
}

# ---------- is Fabric Loader already there, and how old is it? ----------
# Returns one object per Fabric profile for this Minecraft version: the profile id
# and the Fabric Loader version that profile actually loads ('' when unreadable).
function Get-FabricVersions {
    param([string] $Dir, [string] $Mc)
    $found = @()
    $vdir = Join-Path $Dir 'versions'
    if (-not (Test-Path $vdir)) { return $found }
    foreach ($d in Get-ChildItem $vdir -Directory -ErrorAction SilentlyContinue) {
        $json = Join-Path $d.FullName "$($d.Name).json"
        if (-not (Test-Path $json)) { continue }
        try { $o = Get-Content $json -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
        if (-not $o.id) { continue }
        $lib = @($o.libraries | Where-Object { "$($_.name)" -like '*fabric-loader*' } | Select-Object -First 1)
        $looksFabric = ($o.id -like '*fabric*') -or ($lib.Count -gt 0)
        $isTarget    = ($o.inheritsFrom -eq $Mc) -or ($o.id -like "*$Mc*")
        if (-not ($looksFabric -and $isTarget)) { continue }

        $loader = ''
        if ($lib.Count -gt 0 -and "$($lib[0].name)" -match 'fabric-loader:([0-9][0-9.]*)') { $loader = $matches[1] }
        if (-not $loader -and $o.id -match 'fabric-loader-([0-9][0-9.]*)-') { $loader = $matches[1] }
        $found += [pscustomobject]@{ Id = "$($o.id)"; Loader = $loader; Json = $json; SelfContained = (-not $o.inheritsFrom) }
    }
    return $found
}

function Compare-FabricVersion {
    param([string] $A, [string] $B)   # -1 / 0 / 1 ; unparseable versions sort lowest
    try   { $va = [version]$A } catch { return -1 }
    try   { $vb = [version]$B } catch { return 1 }
    return $va.CompareTo($vb)
}

# ---------- find a Java to run the Fabric installer with ----------
function Find-Java {
    param([string] $Dir)
    $cands = @()
    # Java that a launcher already downloaded for you (1.21.1 uses java-runtime-delta = 21)
    Get-ChildItem (Join-Path $Dir 'runtime') -Recurse -Filter 'java.exe' -ErrorAction SilentlyContinue |
        ForEach-Object { $cands += $_.FullName }
    Get-ChildItem (Join-Path $env:APPDATA '.tlauncher\starter') -Recurse -Filter 'java.exe' -ErrorAction SilentlyContinue |
        ForEach-Object { $cands += $_.FullName }
    if ($env:JAVA_HOME) { $cands += (Join-Path $env:JAVA_HOME 'bin\java.exe') }
    foreach ($p in 'C:\Program Files\Java', 'C:\Program Files\Eclipse Adoptium', 'C:\Program Files\Microsoft',
                   'C:\Program Files\Zulu', 'C:\Program Files\Amazon Corretto', 'C:\Program Files\BellSoft',
                   'C:\Program Files\Semeru', 'C:\Program Files\RedHat') {
        Get-ChildItem $p -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { $cands += (Join-Path $_.FullName 'bin\java.exe') }
    }
    $onPath = Get-Command 'java' -ErrorAction SilentlyContinue
    if ($onPath) { $cands += $onPath.Source }

    $best = $null; $bestScore = -1
    foreach ($c in ($cands | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)) {
        $v = & $c -version 2>&1 | Select-Object -First 1
        if ("$v" -match 'version "(\d+)\.(\d+)') {
            $major = [int]$matches[1]
            if ($major -eq 1) { $major = [int]$matches[2] }   # 1.8.0_411 style
            if ($major -lt 8) { continue }
            $score = if ($major -ge 21) { 1000 + $major } else { $major }
            if ($score -gt $bestScore) { $bestScore = $score; $best = $c }
        }
    }
    return $best
}

function Install-Fabric {
    param($GameDir, $Fab, [string] $Java)
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("fabric-installer-" + [guid]::NewGuid().ToString('N') + ".jar")
    try {
        Install-RemoteFile -Uri $Fab.installer.url -OutFile $tmp -ExpectedSize $Fab.installer.size `
            -ExpectedSha512 $Fab.installer.sha512 -Label $Fab.installer.filename | Out-Null

        $argList = @('-jar', $tmp, 'client', '-dir', $GameDir, '-mcversion', $Fab.mcversion, '-loader', $Fab.loader)
        # No launcher_profiles.json -> the installer refuses to run unless told to skip it.
        if (-not (Test-Path (Join-Path $GameDir 'launcher_profiles.json'))) { $argList += '-noprofile' }

        $text = (& $Java @argList 2>&1 | Out-String)
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $text }
    }
    finally {
        if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }
}

# ---------- launchers that ship their own self-contained Fabric profile ----------
# TLauncher writes a Fabric profile whose JSON contains the whole library list and
# inherits nothing, so the official Fabric installer is no use there: it would
# create a profile that inherits vanilla Minecraft, which that launcher often does
# not have. Instead we copy the profile the launcher already trusts and swap only
# its Fabric/ASM/Mixin libraries for the ones Fabric says this loader needs.
function Get-FabricProfile {
    param([string] $Mc, [string] $Loader)
    $uri = "https://meta.fabricmc.net/v2/versions/loader/$Mc/$Loader/profile/json"
    return Invoke-RestMethod -Uri $uri -Headers @{ 'User-Agent' = 'cobblemon-client-installer/1.0' }
}

# Pull one maven artifact into the launcher's libraries folder and check it.
function Install-MavenLibrary {
    param([string] $Name, [string] $RepoUrl, [string] $LibRoot)
    $p       = $Name -split ':'
    $rel     = ($p[0] -replace '\.', '/') + "/$($p[1])/$($p[2])"
    $file    = if ($p.Count -gt 3) { "$($p[1])-$($p[2])-$($p[3]).jar" } else { "$($p[1])-$($p[2]).jar" }
    $relPath = "$rel/$file"
    $dest    = Join-Path $LibRoot ($relPath -replace '/', '\')
    if (Test-Path $dest) { return 'already there' }

    $base = if ($RepoUrl) { $RepoUrl } else { 'https://libraries.minecraft.net/' }
    $url  = $base.TrimEnd('/') + '/' + $relPath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    $wc = New-Object System.Net.WebClient
    try {
        $wc.Headers.Add('User-Agent', 'cobblemon-client-installer/1.0')
        $want = ($wc.DownloadString("$url.sha1")).Trim()
        $wc.DownloadFile($url, $dest)
    } finally { $wc.Dispose() }

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    $fs   = [IO.File]::OpenRead($dest)
    try   { $got = ([BitConverter]::ToString($sha1.ComputeHash($fs)) -replace '-', '').ToLower() }
    finally { $fs.Dispose(); $sha1.Dispose() }
    if ($want -and $got -ne $want.ToLower()) { throw "SHA-1 mismatch for $Name" }
    return 'downloaded'
}

function New-SelfContainedFabricProfile {
    param([string] $GameDir, [string] $SourceJson, [string] $Mc, [string] $Loader)
    $prof = Get-FabricProfile -Mc $Mc -Loader $Loader
    $src  = Get-Content $SourceJson -Raw -Encoding UTF8 | ConvertFrom-Json

    # new Fabric libraries first, then everything the launcher had except its old ones
    $strip = '^(net\.fabricmc:(fabric-loader|intermediary|sponge-mixin)|org\.ow2\.asm:asm)'
    $libs  = @()
    foreach ($l in $prof.libraries) { $libs += [pscustomobject]@{ name = $l.name; url = $l.url } }
    foreach ($l in $src.libraries) { if ("$($l.name)" -notmatch $strip) { $libs += $l } }

    $src.libraries = $libs
    $src.id        = $prof.id
    $src.mainClass = $prof.mainClass

    $dir = Join-Path $GameDir "versions\$($prof.id)"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $out = Join-Path $dir "$($prof.id).json"
    [IO.File]::WriteAllText($out, ($src | ConvertTo-Json -Depth 32), (New-Object System.Text.UTF8Encoding($false)))

    $downloaded = 0
    foreach ($l in $prof.libraries) {
        if ((Install-MavenLibrary -Name $l.name -RepoUrl $l.url -LibRoot (Join-Path $GameDir 'libraries')) -eq 'downloaded') { $downloaded++ }
    }
    return [pscustomobject]@{ Id = $prof.id; Json = $out; Downloaded = $downloaded; Libraries = @($prof.libraries).Count }
}

if (-not (Test-Path $manifestPath)) { throw "mods.json not found next to this script ($scriptDir)." }
$manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

# ---------- pick the game folder ----------
$chosenLauncher = 'given on the command line'
if (-not $GameDir) {
    $cands = @(Find-GameDirs)
    $default = Join-Path $env:APPDATA '.minecraft'
    if ($cands.Count -eq 0) {
        $GameDir = $default
        $chosenLauncher = 'Minecraft launcher (folder will be created)'
    } else {
        $pick = $cands | Where-Object { $_.Path -eq $default } | Select-Object -First 1
        if (-not $pick) { $pick = $cands | Where-Object { Test-Path (Join-Path $_.Path 'versions') } | Select-Object -First 1 }
        if (-not $pick) { $pick = $cands[0] }
        $GameDir = $pick.Path
        $chosenLauncher = $pick.Launcher
    }
    $script:allCands = $cands
}

if (-not (Test-Path $GameDir)) {
    Write-Warn2 "Game folder does not exist yet: $GameDir"
    New-Item -ItemType Directory -Force -Path $GameDir | Out-Null
}
$GameDir = (Resolve-Path $GameDir).Path

Write-Host ""
Write-Host "  Cobblemon client installer" -ForegroundColor White
Write-Host "  Minecraft $($manifest.game) / $($manifest.loader)" -ForegroundColor DarkGray
Write-Host "  game folder : $GameDir" -ForegroundColor DarkGray
Write-Host "  detected as : $chosenLauncher" -ForegroundColor DarkGray
if ($script:allCands -and $script:allCands.Count -gt 1) {
    Write-Host "  also found  :" -ForegroundColor DarkGray
    $script:allCands | Where-Object { $_.Path -ne $GameDir } |
        ForEach-Object { Write-Host "      $($_.Path)  [$($_.Launcher)]" -ForegroundColor DarkGray }
    Write-Host "      (wrong one? re-run with:  install.bat -GameDir ""<path>"")" -ForegroundColor DarkGray
}
Write-Host ""

if (Get-Process -Name javaw -ErrorAction SilentlyContinue) {
    Write-Warn2 "Minecraft is running. New mods only load after a full restart, so close it before playing."
    Write-Host ""
}

# ---------- Fabric Loader ----------
$actuallyPlaying = $true
if ($NoFabric) {
    Write-Step "Fabric Loader - skipped (-NoFabric)"
    Write-Ok "assuming you already have a Fabric profile for $($manifest.game)"
}
elseif (-not $manifest.fabric) {
    Write-Warn2 "mods.json has no fabric section - skipping Fabric Loader"
}
else {
    $fab = $manifest.fabric
    Write-Step "Fabric Loader $($fab.loader) for Minecraft $($fab.mcversion)"
    $have = @(Get-FabricVersions -Dir $GameDir -Mc $fab.mcversion)
    $good = @($have | Where-Object { $_.Loader -and ((Compare-FabricVersion $_.Loader $fab.loader) -ge 0) })

    if ($good.Count -gt 0) {
        Write-Ok "already installed - skipped  ($(($good | ForEach-Object { "$($_.Id) [loader $($_.Loader)]" }) -join ', '))"
        $script:launchProfile = $good[0].Id
    }

    # We have to supply Fabric ourselves. Two different worlds:
    #   * the launcher ships its own self-contained Fabric profile (TLauncher):
    #     copy that profile and swap in the newer Fabric libraries
    #   * any other launcher (normal launcher, Prism, Modrinth App, CurseForge)
    #     has vanilla Minecraft installed, so the official Fabric installer fits
    elseif (@($have | Where-Object { $_.SelfContained }).Count -gt 0) {
        $from = @($have | Where-Object { $_.SelfContained })[0]
        if ($from.Loader) { Write-Warn2 "your launcher's Fabric profile uses Loader $($from.Loader); this mod set needs $($fab.loader)." }
        else              { Write-Warn2 "your launcher's Fabric profile is too old for this mod set." }
        Write-Warn2 "making an upgraded copy next to it (the original is left untouched)."
        try {
            $new = New-SelfContainedFabricProfile -GameDir $GameDir -SourceJson $from.Json -Mc $fab.mcversion -Loader $fab.loader
            Write-Ok "created profile ""$($new.Id)"" - $($new.Libraries) Fabric libraries, $($new.Downloaded) downloaded"
            $script:launchProfile = $new.Id
        } catch {
            Write-Warn2 "could not create it automatically: $($_.Exception.Message)"
            Write-Warn2 "install Fabric Loader $($fab.loader) yourself: https://fabricmc.net/use/installer/"
        }
    }
    else {
        $java = Find-Java -Dir $GameDir
        if (-not $java) {
            Write-Warn2 "No Java found, so Fabric cannot be installed automatically."
            Write-Warn2 "Install Java 21 from https://adoptium.net and re-run, or use the"
            Write-Warn2 "official Fabric installer: https://fabricmc.net/use/installer/"
        }
        else {
            Write-Ok "using Java: $java"
            $res = Install-Fabric -GameDir $GameDir -Fab $fab -Java $java
            if ($res.ExitCode -eq 0) {
                $have = @(Get-FabricVersions -Dir $GameDir -Mc $fab.mcversion)
                if ($have.Count -gt 0) {
                    Write-Ok "installed ($(($have | ForEach-Object { $_.Id }) -join ', '))"
                    $script:launchProfile = $have[0].Id
                }
                else { Write-Warn2 "the installer reported success but no Fabric version turned up" }
            }
            else {
                Write-Warn2 "the Fabric installer failed (exit code $($res.ExitCode)):"
                ($res.Output -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Last 5 |
                    ForEach-Object { Write-Warn2 "  $_" }
            }
        }
    }

    # A profile from the official installer inherits vanilla Minecraft $Mc, so the
    # launcher needs vanilla $Mc installed as well. Self-contained profiles do not.
    $selfNow     = @(Get-FabricVersions -Dir $GameDir -Mc $fab.mcversion | Where-Object { $_.SelfContained })
    $vanillaJson = Join-Path $GameDir "versions\$($fab.mcversion)\$($fab.mcversion).json"
    if ($selfNow.Count -eq 0 -and -not (Test-Path $vanillaJson)) {
        Write-Warn2 "Minecraft $($fab.mcversion) itself is not installed in this folder yet."
        Write-Warn2 "Start Minecraft $($fab.mcversion) once from your launcher, then re-run this."
        $actuallyPlaying = $false
    }
}

# ---------- launcher mods the pack refuses to run with ----------
# Fabric Loader will not start when a mod is present that another mod declares
# under "breaks". Cracked launchers ship their own skin/cape mod (TLauncher's has
# the mod id "tlskincape"), and two of the pack's mods declare that they break it,
# so we keep the launcher's mod - it is what draws every player's skin - and skip
# those two instead of letting Minecraft fail on the very first launch.
$skipEntries = @{}
foreach ($rule in @([pscustomobject]@{ Present = 'tl_skin_cape*.jar'; Skip = @('Entity Culling', 'Not Enough Animations') })) {
    $hit = Get-ChildItem (Join-Path $GameDir 'mods') -Filter $rule.Present -File -ErrorAction SilentlyContinue
    if (-not $hit) { continue }
    foreach ($s in $rule.Skip) { $skipEntries[$s] = $hit[0].Name }
}

$entries = $manifest.files
if ($Minimal) { $entries = $entries | Where-Object { $_.core } }

$results  = @()
$stale    = @()
$bytesGot = 0

foreach ($e in $entries) {
    $destDir = Join-Path $GameDir $e.folder
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    $target = Join-Path $destDir $e.filename

    Write-Step "$($e.name) $($e.version)  ($([math]::Round($e.size/1MB,1)) MB)"

    if ($skipEntries.ContainsKey($e.name)) {
        Write-Warn2 "skipped on purpose: Fabric refuses to start while it sits next to"
        Write-Warn2 "$($skipEntries[$e.name]) (your launcher's skin/cape mod)."
        if (Test-Path $target) {
            Remove-Item $target -Force
            Write-Warn2 "removed the copy installed earlier."
        }
        $results += [pscustomobject]@{ Name = $e.name; Status = 'skipped (conflict)'; File = $e.filename }
        continue
    }

    # is the exact right content already there?
    $needDownload = $true
    if ((Test-Path $target) -and -not $Force) {
        if ((Get-Sha512Hex $target) -eq $e.sha512.ToLower()) {
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

# ---------- client config: minimap corner ----------
$minimapSet = $false
if (-not $Minimal -and -not $KeepMinimapPosition) {
    Write-Step "Xaero's Minimap"
    [void](Set-MinimapTopRight -GameDir $GameDir)
    Write-Ok "minimap corner set to the top right (config\xaerohud.txt)"
    $minimapSet = $true
    if (Get-Process -Name javaw -ErrorAction SilentlyContinue) {
        Write-Warn2 "Minecraft is open right now - it rewrites that file when it closes."
        Write-Warn2 "If the map is back on the left afterwards, re-run install.bat once the game is closed."
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
if ($actuallyPlaying) {
    Write-Host "    1. Launch Minecraft $($manifest.game) with Fabric:"
    if ($script:launchProfile) {
        Write-Host "         pick this profile -> ""$($script:launchProfile)""" -ForegroundColor White
    } elseif ($manifest.fabric) {
        Write-Host "         normal launcher -> ""fabric-loader-$($manifest.fabric.loader)-$($manifest.game)"""
        Write-Host "         TLauncher       -> ""Fabric $($manifest.game)"""
    } else {
        Write-Host "         use your usual Fabric profile for $($manifest.game)"
    }
    Write-Host "         (TLauncher lists it at the top-left version box, the normal launcher"
    Write-Host "          under Installations; Prism/Modrinth/CurseForge = the instance you chose)"
} else {
    Write-Host "    1. Run Minecraft $($manifest.game) once from your launcher, then re-run install.bat."
    Write-Host "       Then pick the Fabric profile and launch."
}
if (-not $Minimal) {
    Write-Host "    2. Shaders: Options -> Video Settings -> Shader Packs -> pick Complementary Reimagined -> Apply."
    Write-Host "       (That menu only exists after a full restart, because Sodium/Iris load at startup.)"
    if ($minimapSet) {
        Write-Host "    3. Minimap: Xaero's now sits in the top right corner."
        Write-Host "       Press Y in game to move, resize or hide it."
    }
}
Write-Host ""
Write-Host "  Done." -ForegroundColor Green
