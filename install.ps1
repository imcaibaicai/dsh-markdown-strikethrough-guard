# install.ps1 -- install or uninstall dsh-markdown-strikethrough-guard plugin.
#
# Usage:
#   .\install.ps1            # install and configure
#   .\install.ps1 -Uninstall  # cleanly revert junction and cordis.patch.yml row

param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceDir = $scriptDir

if (-not (Test-Path (Join-Path $sourceDir 'package.json'))) {
    throw "plugin source package.json not found in: $sourceDir"
}

$dshHome = 'D:\DeepSeekHarness\.dsh'
if ($env:DSH_HOME -and (Test-Path $env:DSH_HOME)) {
    $dshHome = $env:DSH_HOME
}

$profilesNodeModules = Join-Path $dshHome 'profiles\node_modules'
$webNodeModules      = Join-Path $dshHome 'profiles\web\node_modules'
$patchFile           = Join-Path $dshHome 'profiles\web\cordis.patch.yml'

$targetProfiles = Join-Path $profilesNodeModules 'dsh-markdown-strikethrough-guard'
$targetWeb      = Join-Path $webNodeModules 'dsh-markdown-strikethrough-guard'

$rowComment = "# Markdown strikethrough guard: escape lone tildes in ranges"
$rowEntry = @(
    "- insert:",
    "    - id: markdown-strikethrough-guard",
    "      name: 'dsh-markdown-strikethrough-guard'"
)

# ----------------- UNINSTALL -----------------
if ($Uninstall) {
    Write-Host "[Uninstall] Removing junctions..." -ForegroundColor Cyan

    if (Test-Path $targetProfiles) {
        Write-Host "  Removing junction: $targetProfiles"
        [System.IO.Directory]::Delete($targetProfiles, $false)
    }
    if (Test-Path $targetWeb) {
        Write-Host "  Removing junction: $targetWeb"
        [System.IO.Directory]::Delete($targetWeb, $false)
    }

    if (Test-Path $patchFile) {
        Write-Host "  Reverting cordis.patch.yml..."
        $content = Get-Content -Path $patchFile -Raw -Encoding UTF8
        # Remove inserted block
        $pattern = "(?ms)\r?\n# Markdown strikethrough guard[^\r\n]*\r?\n- insert:\r?\n\s+- id: markdown-strikethrough-guard\r?\n\s+name: ['`"]dsh-markdown-strikethrough-guard['`"]"
        $newContent = [System.Text.RegularExpressions.Regex]::Replace($content, $pattern, "")
        if ($newContent -ne $content) {
            Set-Content -Path $patchFile -Value $newContent -Encoding UTF8
            Write-Host "  Removed patch entry from cordis.patch.yml" -ForegroundColor Green
        }
    }

    Write-Host "[Uninstall] Completed cleanly." -ForegroundColor Green
    return
}

# ------------------ INSTALL ------------------
Write-Host "[Install] Installing dsh-markdown-strikethrough-guard..." -ForegroundColor Cyan

# 1. Ensure node_modules directories exist
if (-not (Test-Path $profilesNodeModules)) {
    New-Item -ItemType Directory -Path $profilesNodeModules -Force | Out-Null
}

# 2. Create Junction in profiles/node_modules
if (Test-Path $targetProfiles) {
    Write-Host "  Target junction already exists: $targetProfiles" -ForegroundColor Yellow
} else {
    Write-Host "  Creating junction: $targetProfiles -> $sourceDir"
    New-Item -ItemType Junction -Path $targetProfiles -Target $sourceDir | Out-Null
}

# 3. Create Junction in profiles/web/node_modules if present
if (Test-Path $webNodeModules) {
    if (-not (Test-Path $targetWeb)) {
        Write-Host "  Creating junction: $targetWeb -> $sourceDir"
        New-Item -ItemType Junction -Path $targetWeb -Target $sourceDir | Out-Null
    }
}

# 4. Patch cordis.patch.yml
if (Test-Path $patchFile) {
    $content = Get-Content -Path $patchFile -Raw -Encoding UTF8
    if ($content -match "markdown-strikethrough-guard") {
        Write-Host "  cordis.patch.yml already has markdown-strikethrough-guard row." -ForegroundColor Yellow
    } else {
        # Backup before modify
        $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
        $bakFile = "$patchFile.bak-guard-$timestamp"
        Copy-Item -Path $patchFile -Destination $bakFile
        Write-Host "  Backed up cordis.patch.yml to $bakFile" -ForegroundColor Gray

        $blockToAppend = "`r`n$rowComment`r`n" + ($rowEntry -join "`r`n") + "`r`n"
        Add-Content -Path $patchFile -Value $blockToAppend -Encoding UTF8
        Write-Host "  Appended loader row to $patchFile" -ForegroundColor Green
    }
} else {
    Write-Warning "patchFile not found: $patchFile"
}

Write-Host "[Install] Success! Full restart of DSH is required for host loader row to take effect." -ForegroundColor Green
