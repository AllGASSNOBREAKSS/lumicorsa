<#
.SYNOPSIS
  Installs PHOTOLAP into Assetto Corsa. Needs only Content Manager + Custom Shaders Patch.

.DESCRIPTION
  Copies the CSP app folder into assettocorsa\apps\lua\Photolap. That's it: no ReShade, no DLLs, no other files.
  Finds Assetto Corsa through your Steam libraries, or pass -AcPath. Re-running updates in place; your panel settings
  live in Documents\Assetto Corsa\cfg and are kept. -Uninstall removes the app folder.

  (The optional ReShade path from v0.1 lives in legacy\reshade\Install-Legacy-ReShade.ps1.)

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\installer\Install-Photolap.ps1
  powershell -ExecutionPolicy Bypass -File .\installer\Install-Photolap.ps1 -AcPath "D:\SteamLibrary\steamapps\common\assettocorsa"
#>
[CmdletBinding()]
param(
    [string]$AcPath,
    [string]$PackageDir,
    [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 leaves $PSScriptRoot empty inside param() defaults, so resolve it here.
if (-not $PackageDir) { $PackageDir = Split-Path -Parent $PSScriptRoot }

function Say($t, $c = 'Gray') { Write-Host $t -ForegroundColor $c }
function Ok($t)   { Say "  [ok]   $t" 'Green' }
function Warn($t) { Say "  [!]    $t" 'Yellow' }
function Fail($t) { Say "  [x]    $t" 'Red'; exit 1 }

Say ''
Say '  P H O T O L A P   //  photoreal for Assetto Corsa' 'Magenta'
Say ''

function Find-AssettoCorsa {
    $steam = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if (-not $steam) { return $null }
    $libs = @($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) { $libs += $m.Groups[1].Value -replace '\\\\', '\' }
    }
    foreach ($l in $libs | Select-Object -Unique) {
        $p = Join-Path $l 'steamapps\common\assettocorsa'
        if (Test-Path (Join-Path $p 'acs.exe')) { return $p }
    }
    return $null
}
if (-not $AcPath) { $AcPath = Find-AssettoCorsa }
if (-not $AcPath -or -not (Test-Path (Join-Path $AcPath 'acs.exe'))) { Fail 'Assetto Corsa not found. Pass -AcPath "<...>\steamapps\common\assettocorsa".' }
Ok "Assetto Corsa: $AcPath"

$target = Join-Path $AcPath 'apps\lua\Photolap'

if ($Uninstall) {
    if (Test-Path $target) { Remove-Item $target -Recurse -Force; Ok 'Photolap removed' } else { Warn 'Photolap is not installed' }
    exit 0
}

if (-not (Test-Path (Join-Path $AcPath 'extension')) -or -not (Test-Path (Join-Path $AcPath 'dwrite.dll'))) {
    Fail 'Custom Shaders Patch not found. Install it in Content Manager > Settings > Custom Shaders Patch first.'
}
Ok 'Custom Shaders Patch found'

$source = @('csp-app\Photolap', 'apps\lua\Photolap') | ForEach-Object { Join-Path $PackageDir $_ } |
    Where-Object { Test-Path (Join-Path $_ 'manifest.ini') } | Select-Object -First 1
if (-not $source) { Fail "Photolap app folder not found under $PackageDir" }

if (Test-Path $target) { Remove-Item $target -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
Copy-Item $source $target -Recurse -Force
Ok "Installed to $target"

# v0.1 left ReShade files in the AC folder; 0.2 doesn't use them. Point them out, don't touch them.
$legacy = @('photolap.addon64', 'PhotolapPreset.ini', 'reshade-shaders\Shaders\Photolap') |
    Where-Object { Test-Path (Join-Path $AcPath $_) }
if ($legacy) { Warn ("Unused v0.1 ReShade files (safe to delete): " + ($legacy -join ', ')) }

Say ''
Say '  Done. Start a session from Content Manager, then open Photolap from the CSP apps bar (or press Alt+P).' 'Cyan'
Say '  Alt+O = instant bypass. For upscaling, enable DLSS/FSR in CM > Settings > Custom Shaders Patch.' 'Cyan'
Say ''
