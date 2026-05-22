# Phase 2: AMD Chipset + Intel DTT/SST/Platform seed packages
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$PkgDir = Join-Path $Root 'packages'
$Work = Join-Path $env:TEMP 'driver_mirror_phase2'
Remove-Item $Work -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $PkgDir, $Work | Out-Null

function Write-SourceTxt {
    param(
        [string]$Path,
        [string]$Title,
        [string]$Version = '',
        [string]$UpdateId = '',
        [string]$SourceUrl = '',
        [string[]]$HardwareIds = @(),
        [string]$InstallHint = ''
    )
    $lines = @("Title: $Title")
    if ($Version) { $lines += "Version: $Version" }
    if ($UpdateId) { $lines += "Microsoft Update Catalog UpdateId: $UpdateId" }
    if ($SourceUrl) { $lines += $SourceUrl }
    foreach ($id in $HardwareIds) { $lines += "Hardware ID: $id" }
    if ($InstallHint) { $lines += "Install: $InstallHint" }
    Set-Content -Path $Path -Value ($lines -join "`r`n") -Encoding UTF8
}

function New-FlatZip {
    param([string]$SourceDir, [string]$ZipPath, [string]$SourceTxtPath)
    if ($SourceTxtPath -and (Test-Path $SourceTxtPath)) {
        Copy-Item $SourceTxtPath (Join-Path $SourceDir 'source.txt') -Force
    }
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
    $items = Get-ChildItem $SourceDir -Force
    if (-not $items) { throw "Empty source dir: $SourceDir" }
    Compress-Archive -Path (Join-Path $SourceDir '*') -DestinationPath $ZipPath -Force
}

function Build-FromPnPMulti {
    param(
        [string[]]$PublishedInfs,
        [string]$ZipName,
        [string]$Title,
        [string]$Version,
        [string[]]$HardwareIds = @(),
        [string]$SourceUrl = ''
    )
    $flat = Join-Path $Work ($ZipName + '-flat')
    Remove-Item $flat -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $flat | Out-Null
    foreach ($published in $PublishedInfs) {
        Write-Host "Exporting $published for $ZipName ..."
        $stage = Join-Path $Work ($ZipName + '-' + $published)
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        pnputil /export-driver $published $stage | Out-Null
        Get-ChildItem $stage -Recurse -File | ForEach-Object {
            $dest = Join-Path $flat $_.Name
            if (Test-Path $dest) {
                $dest = Join-Path $flat ($published + '_' + $_.Name)
            }
            Copy-Item $_.FullName $dest -Force
        }
    }
    $srcTxt = Join-Path $Work ($ZipName + '-source.txt')
    Write-SourceTxt -Path $srcTxt -Title $Title -Version $Version -SourceUrl $SourceUrl -HardwareIds $HardwareIds
    New-FlatZip -SourceDir $flat -ZipPath (Join-Path $PkgDir $ZipName) -SourceTxtPath $srcTxt
}

Write-Host '=== Phase 2 package build ==='

# AMD Chipset: official installer (NSIS, requires silent /S install)
$amdExeName = 'amd_chipset_software_8.05.04.516.exe'
$amdExe = Join-Path $Work $amdExeName
$amdUrl = 'https://github.com/notFoxils/AMD-Chipset-Drivers/releases/download/8.05.04.516/' + $amdExeName
Write-Host 'Downloading AMD Chipset installer ...'
Invoke-WebRequest -Uri $amdUrl -OutFile $amdExe -UseBasicParsing -TimeoutSec 600
$amdStage = Join-Path $Work 'amd_chipset'
Remove-Item $amdStage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $amdStage | Out-Null
Copy-Item $amdExe (Join-Path $amdStage $amdExeName) -Force
Set-Content -Path (Join-Path $amdStage 'install_silent.cmd') -Value "@echo off`r`n""%~dp0$amdExeName"" /S`r`n" -Encoding ASCII
$hwidsAmd = @(
    'PCI\VEN_1022&DEV_15D4',
    'PCI\VEN_1022&DEV_790B',
    'PCI\VEN_1022&DEV_780B',
    'PCI\VEN_1022&DEV_1482',
    'PCI\VEN_1022&DEV_1671'
)
$amdSrc = Join-Path $Work 'amd_chipset-source.txt'
Write-SourceTxt -Path $amdSrc -Title 'AMD Ryzen Chipset' -Version '8.05.04.516' -SourceUrl $amdUrl -HardwareIds $hwidsAmd -InstallHint "Run $amdExeName /S as Administrator"
New-FlatZip -SourceDir $amdStage -ZipPath (Join-Path $PkgDir 'amd_chipset.zip') -SourceTxtPath $amdSrc

# Intel DTT (Dynamic Platform/Tuning Technology, dptf)
$hwidsDtt = @('PCI\VEN_8086&DEV_9A03', 'PCI\VEN_8086&DEV_A0DE', 'PCI\VEN_8086&DEV_98A4', 'ACPI\INT3400')
Build-FromPnPMulti -PublishedInfs @('oem16.inf', 'oem17.inf') -ZipName 'intel_dtt.zip' -Title 'Intel DTT / DPTF' -Version '8.7.10802.26924' -HardwareIds $hwidsDtt

# Intel SST (Smart Sound Technology audio)
$hwidsSst = @('PCI\VEN_8086&DEV_A0C8', 'PCI\VEN_8086&DEV_51CA', 'PCI\VEN_8086&DEV_7A50', 'HDAUDIO\FUNC_01&VEN_8086&DEV_2812')
Build-FromPnPMulti -PublishedInfs @('oem5.inf', 'oem3.inf') -ZipName 'intel_sst.zip' -Title 'Intel Smart Sound Technology' -Version '11.2.0.15' -HardwareIds $hwidsSst

# Intel Platform components (ICLS, DAL, ME WMI provider)
$hwidsPlatform = @('PCI\VEN_8086&DEV_43E0', 'SWD\DRIVERENUM\ICLSCLIENT', 'SWD\DRIVERENUM\DAL')
Build-FromPnPMulti -PublishedInfs @('oem11.inf', 'oem12.inf', 'oem10.inf') -ZipName 'intel_platform.zip' -Title 'Intel Platform Components' -Version '1.71.99.0' -HardwareIds $hwidsPlatform

Write-Host ''
Write-Host '=== Phase 2 SHA256 ==='
@('amd_chipset.zip', 'intel_dtt.zip', 'intel_sst.zip', 'intel_platform.zip') | ForEach-Object {
    $path = Join-Path $PkgDir $_
    if (-not (Test-Path $path)) { Write-Warning "Missing $_"; return }
    $hash = (Get-FileHash $path -Algorithm SHA256).Hash.ToLower()
    $mb = [math]::Round((Get-Item $path).Length / 1MB, 2)
    Write-Output ("{0}`t{1} MB`t{2}" -f $_, $mb, $hash)
}
