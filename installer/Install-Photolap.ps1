<#
.SYNOPSIS
  Installs PHOTOLAP into Assetto Corsa (Content Manager + Custom Shaders Patch).

.DESCRIPTION
  1. Finds Assetto Corsa (Steam library scan, or -AcPath).
  2. Checks Custom Shaders Patch is installed (required: Photolap's in-game panel is a CSP Lua app,
     and CSP Preview 338+ is what provides real DLSS motion vectors/depth for the neural pass).
  3. Installs ReShade (add-on build, from reshade.me) as dxgi.dll next to acs.exe, unless one is present.
  4. Copies Photolap.fx, photolap.addon64, the CSP app, ReShade.ini + PhotolapPreset.ini.
  5. Reports the neural (DLSS 5) backend state. It never downloads NVIDIA binaries: see README > Neural setup.

  Re-running is safe. -Uninstall removes only what this script placed (tracked in photolap-install.json).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Install-Photolap.ps1
  powershell -ExecutionPolicy Bypass -File .\Install-Photolap.ps1 -AcPath "D:\SteamLibrary\steamapps\common\assettocorsa"
#>
[CmdletBinding()]
param(
    [string]$AcPath,
    [string]$PackageDir = (Split-Path -Parent $PSScriptRoot),
    [string]$ReShadeSetup,          # optional local ReShade_Setup_*_Addon.exe
    [switch]$SkipReShade,
    [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'
$AppId = 244210

function Say($t, $c = 'Gray') { Write-Host $t -ForegroundColor $c }
function Ok($t)   { Say "  [ok]   $t" 'Green' }
function Warn($t) { Say "  [!]    $t" 'Yellow' }
function Fail($t) { Say "  [x]    $t" 'Red'; exit 1 }

Say ''
Say '  P H O T O L A P   //  neural photoreal for Assetto Corsa' 'Magenta'
Say ''

# ------------------------------------------------------------------------------------------ locate AC
function Find-AssettoCorsa {
    $steam = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if (-not $steam) { return $null }
    $libs = @($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) { $libs += $m.Groups[1].Value -replace '\\\\', '\' }
    }
    foreach ($l in $libs | Select-Object -Unique) {
        if (Test-Path (Join-Path $l "steamapps\appmanifest_$AppId.acf")) {
            $p = Join-Path $l 'steamapps\common\assettocorsa'
            if (Test-Path (Join-Path $p 'acs.exe')) { return $p }
        }
    }
    return $null
}
if (-not $AcPath) { $AcPath = Find-AssettoCorsa }
if (-not $AcPath -or -not (Test-Path (Join-Path $AcPath 'acs.exe'))) { Fail 'Assetto Corsa not found. Pass -AcPath "<...>\steamapps\common\assettocorsa".' }
Ok "Assetto Corsa: $AcPath"

$ManifestPath = Join-Path $AcPath 'photolap-install.json'
$placed = New-Object System.Collections.Generic.List[string]

# ------------------------------------------------------------------------------------------ uninstall
if ($Uninstall) {
    if (-not (Test-Path $ManifestPath)) { Fail 'Nothing to uninstall (no photolap-install.json).' }
    $m = Get-Content $ManifestPath -Raw | ConvertFrom-Json
    foreach ($f in $m.files) { $p = Join-Path $AcPath $f; if (Test-Path $p) { Remove-Item $p -Recurse -Force; Ok "removed $f" } }
    Remove-Item $ManifestPath -Force
    Ok 'Photolap removed. ReShade was only removed if this script installed it.'
    exit 0
}

# ------------------------------------------------------------------------------------------ CSP
$csp = Join-Path $AcPath 'extension'
if (-not (Test-Path $csp) -or -not (Test-Path (Join-Path $AcPath 'dwrite.dll'))) {
    Fail 'Custom Shaders Patch not found. Install it in Content Manager > Settings > Custom Shaders Patch first.'
}
Ok 'Custom Shaders Patch found'
$dlssDll = Get-ChildItem -Path (Join-Path $csp 'internal') -Filter 'nvngx_dlss.dll' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($dlssDll) { Ok "CSP ships DLSS (nvngx_dlss.dll $((Get-Item $dlssDll.FullName).VersionInfo.FileVersion))" }
else { Warn 'No nvngx_dlss.dll under extension\internal: CSP DLSS (Preview 338+) is needed for the neural pass. Post stack still works.' }

# ------------------------------------------------------------------------------------------ ReShade
function Find-ZipEntry($zip, $pattern) { $zip.Entries | Where-Object { $_.FullName -match $pattern } | Select-Object -First 1 }
$dxgi = Join-Path $AcPath 'dxgi.dll'
$hasReShade = (Test-Path $dxgi) -and ((Get-Item $dxgi).VersionInfo.ProductName -match 'ReShade')
if ($hasReShade) { Ok "ReShade already installed ($((Get-Item $dxgi).VersionInfo.ProductVersion))" }
elseif ($SkipReShade) { Warn 'ReShade not installed (-SkipReShade).' }
else {
    if (-not $ReShadeSetup) {
        Say '  ...    fetching ReShade (add-on build) from reshade.me'
        $page = (Invoke-WebRequest -UseBasicParsing -Uri 'https://reshade.me').Content
        $m = [regex]::Match($page, 'downloads/ReShade_Setup_([0-9.]+)_Addon\.exe')
        $url = if ($m.Success) { 'https://reshade.me/' + $m.Value } else { 'https://reshade.me/downloads/ReShade_Setup_6.8.0_Addon.exe' }
        $ReShadeSetup = Join-Path $env:TEMP ([IO.Path]::GetFileName($url))
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $ReShadeSetup
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($ReShadeSetup)   # the setup exe carries a zip payload
    try {
        $e = Find-ZipEntry $zip '^ReShade64\.dll$'
        if (-not $e) { Fail 'ReShade64.dll not found inside the ReShade setup.' }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dxgi, $true)
    } finally { $zip.Dispose() }
    $placed.Add('dxgi.dll')
    Ok 'ReShade installed as dxgi.dll'
}

# ------------------------------------------------------------------------------------------ Photolap files
function Place($srcRel, $dstRel) {
    $src = Join-Path $PackageDir $srcRel
    $dst = Join-Path $AcPath $dstRel
    if (-not (Test-Path $src)) { Fail "package is missing $srcRel" }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
    Copy-Item $src $dst -Recurse -Force
    $placed.Add($dstRel)
}
Place 'shaders\Photolap.fx' 'reshade-shaders\Shaders\Photolap\Photolap.fx'
Place 'bin\photolap.addon64' 'photolap.addon64'
Place 'csp-app\Photolap' 'apps\lua\Photolap'
Ok 'Shader, add-on and in-game app installed'

$ini = Join-Path $AcPath 'ReShade.ini'
if (-not (Test-Path $ini)) {
@"
[GENERAL]
EffectSearchPaths=.\reshade-shaders\Shaders\**
TextureSearchPaths=.\reshade-shaders\Textures\**
PresetPath=.\PhotolapPreset.ini
PerformanceMode=1
NoReloadOnInit=0

[INPUT]
KeyOverlay=36,0,0,0
KeyEffects=0,0,0,0

[ADDON]
DisabledAddons=

[OVERLAY]
TutorialProgress=4
"@ | Set-Content -Path $ini -Encoding ASCII
    $placed.Add('ReShade.ini')
    Ok 'ReShade.ini written'
} else { Warn 'Existing ReShade.ini kept. Set PresetPath=.\PhotolapPreset.ini to use the Photolap preset.' }

$preset = Join-Path $AcPath 'PhotolapPreset.ini'
@"
Techniques=Photolap_Light@Photolap.fx,Photolap_Atmos@Photolap.fx,Photolap_Detail@Photolap.fx,Photolap_Lens@Photolap.fx
TechniqueSorting=Photolap_Light@Photolap.fx,Photolap_Atmos@Photolap.fx,Photolap_Detail@Photolap.fx,Photolap_Lens@Photolap.fx
PreprocessorDefinitions=PL_DEPTH_REVERSED=0,PL_DEPTH_UPSIDE_DOWN=0,PL_DEPTH_FAR_PLANE=1000.0
"@ | Set-Content -Path $preset -Encoding ASCII
$placed.Add('PhotolapPreset.ini')

# ------------------------------------------------------------------------------------------ neural backend report
$reno = Get-ChildItem -Path $AcPath -Filter 'renodx-dlss5*.addon64' -ErrorAction SilentlyContinue | Select-Object -First 1
$nr   = Test-Path (Join-Path $AcPath 'nvngx_dlssnr.dll')
if ($reno -and $nr) { Ok "Neural backend: $($reno.Name) + nvngx_dlssnr.dll (live control via Photolap panel)" }
else { Warn 'Neural (DLSS 5) backend not found. Photolap''s post stack works on any GPU; the neural pass needs an RTX 50 + a DLSS 5 neural backend. See README > Neural setup.' }

# ------------------------------------------------------------------------------------------ record
$old = if (Test-Path $ManifestPath) { (Get-Content $ManifestPath -Raw | ConvertFrom-Json).files } else { @() }
@{ version = '0.1.0'; installed = (Get-Date).ToString('s'); files = @(@($old) + @($placed) | Select-Object -Unique) } |
    ConvertTo-Json | Set-Content -Path $ManifestPath -Encoding UTF8

Say ''
Say '  Done. In Content Manager: Settings > Custom Shaders Patch > Upscaler -> NVIDIA DLSS (DLAA or Quality).' 'Cyan'
Say '  In game: open "Photolap" from the CSP apps bar or press Alt+P.  Alt+O = instant bypass.' 'Cyan'
Say ''
