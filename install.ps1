# install.ps1 -- install / uninstall dsh-markdown-strikethrough-guard into ALL DSH profiles.
#
# Why "all profiles": the running DeepSeek Harness.exe host loads exactly ONE
# profile directory (its command line names it, e.g. ...\.dsh\profiles\desktop).
# A plugin installed only into profiles\web is never loaded -- that was exactly
# the v0.1.0 bug this rewrite fixes. We therefore junction the package into every
# profile node_modules dir and append one loader row to every profile
# cordis.patch.yml.
#
# Usage:
#   .\install.ps1             # install into every profile found
#   .\install.ps1 -Uninstall  # remove junctions + loader rows again
#
# NOTE: intentionally ASCII-only (Windows PowerShell 5.1 reads BOM-less UTF-8 as
# the ANSI codepage; non-ASCII literals then corrupt the config file).
# NOTE: removing a junction MUST use [System.IO.Directory]::Delete($p,$false);
# Remove-Item -Recurse would follow the link and delete the real package.

param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceDir = $scriptDir
$pkgName   = 'dsh-markdown-strikethrough-guard'

if (-not (Test-Path (Join-Path $sourceDir 'package.json'))) {
    throw "plugin source package.json not found in: $sourceDir"
}

# ---------- resolve DSH home ----------
$dshHome = $null
if ($env:DSH_HOME -and (Test-Path (Join-Path $env:DSH_HOME 'profiles'))) {
    $dshHome = $env:DSH_HOME
} elseif (Test-Path 'D:\DeepSeekHarness\.dsh\profiles') {
    $dshHome = 'D:\DeepSeekHarness\.dsh'
} elseif ($env:USERPROFILE -and (Test-Path (Join-Path $env:USERPROFILE '.dsh\profiles'))) {
    $dshHome = Join-Path $env:USERPROFILE '.dsh'
}
if (-not $dshHome) { throw "cannot locate DSH home (no profiles dir found)" }

$profilesDir = Join-Path $dshHome 'profiles'
Write-Host "DSH home : $dshHome" -ForegroundColor Cyan

# ---------- discover targets ----------
# Every profile directory that owns a cordis.patch.yml is a loader target.
$targets = @()
foreach ($dir in (Get-ChildItem $profilesDir -Directory -ErrorAction SilentlyContinue)) {
    if ($dir.Name -like '*.bak-*') { continue }
    if ($dir.Name -like 'lib-backup-*') { continue }
    if ($dir.Name -like 'pf-lib-backup-*') { continue }
    if ($dir.Name -eq 'node_modules') { continue }
    $patch = Join-Path $dir.FullName 'cordis.patch.yml'
    if (Test-Path $patch) {
        $targets += [pscustomobject]@{
            Profile = $dir.Name
            Patch   = $patch
            Modules = Join-Path $dir.FullName 'node_modules'
            Link    = Join-Path (Join-Path $dir.FullName 'node_modules') $pkgName
        }
    }
}
# profiles\node_modules is shared by every profile package, so link it too.
$sharedModules = Join-Path $profilesDir 'node_modules'
$sharedLink    = Join-Path $sharedModules $pkgName

if ($targets.Count -eq 0) { throw "no profile cordis.patch.yml found under $profilesDir" }

Write-Host ("profiles : " + (($targets | ForEach-Object { $_.Profile }) -join ', ')) -ForegroundColor Cyan
Write-Host ''

$rowComment = '# Markdown strikethrough guard: escape lone tildes in ranges (6~8) so GFM singleTilde cannot strike them through'
$rowBlock = @(
    $rowComment,
    '- insert:',
    '    - id: markdown-strikethrough-guard',
    "      name: '$pkgName'"
)

# ------------------ UNINSTALL ------------------
if ($Uninstall) {
    foreach ($link in (@($sharedLink) + @($targets | ForEach-Object { $_.Link }))) {
        if (Test-Path $link) {
            [System.IO.Directory]::Delete($link, $false)
            Write-Host "  removed junction: $link" -ForegroundColor Yellow
        }
    }
    foreach ($t in $targets) {
        $content = Get-Content -Path $t.Patch -Raw -Encoding UTF8
        $pattern = '(?ms)\r?\n# Markdown strikethrough guard[^\r\n]*\r?\n- insert:\r?\n\s+- id: markdown-strikethrough-guard\r?\n\s+name: ''[^'']*'''
        $new = [System.Text.RegularExpressions.Regex]::Replace($content, $pattern, '')
        if ($new -ne $content) {
            Set-Content -Path $t.Patch -Value $new -Encoding UTF8
            Write-Host "  removed loader row from $($t.Patch)" -ForegroundColor Yellow
        }
    }
    Write-Host '[Uninstall] done. Restart DSH to revert to stock behaviour.' -ForegroundColor Green
    return
}

# ------------------ INSTALL ------------------
$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')

if (-not (Test-Path $sharedModules)) { New-Item -ItemType Directory -Path $sharedModules -Force | Out-Null }
if (-not (Test-Path $sharedLink)) {
    New-Item -ItemType Junction -Path $sharedLink -Target $sourceDir | Out-Null
    Write-Host "  + junction (shared): $sharedLink" -ForegroundColor Green
} else {
    Write-Host "  = junction exists  : $sharedLink" -ForegroundColor DarkGray
}

foreach ($t in $targets) {
    Write-Host "[$($t.Profile)]" -ForegroundColor Cyan
    if (-not (Test-Path $t.Modules)) { New-Item -ItemType Directory -Path $t.Modules -Force | Out-Null }
    if (-not (Test-Path $t.Link)) {
        New-Item -ItemType Junction -Path $t.Link -Target $sourceDir | Out-Null
        Write-Host "  + junction: $($t.Link)" -ForegroundColor Green
    } else {
        Write-Host "  = junction exists: $($t.Link)" -ForegroundColor DarkGray
    }

    $content = Get-Content -Path $t.Patch -Raw -Encoding UTF8
    if ($content -match 'markdown-strikethrough-guard') {
        Write-Host "  = loader row already present" -ForegroundColor DarkGray
    } else {
        $bak = "$($t.Patch).bak-guard-$stamp"
        Copy-Item -Path $t.Patch -Destination $bak
        Write-Host "  ~ backup: $bak" -ForegroundColor DarkGray
        $append = "`r`n" + ($rowBlock -join "`r`n") + "`r`n"
        Add-Content -Path $t.Patch -Value $append -Encoding UTF8
        Write-Host "  + loader row appended" -ForegroundColor Green
    }
}

Write-Host ''
Write-Host '[Install] done.' -ForegroundColor Green
Write-Host 'IMPORTANT: the host loads plugin rows at startup -- fully quit and restart DeepSeek Harness.' -ForegroundColor Yellow
