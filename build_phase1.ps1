# Phase 1: build mirror seed packages
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$PkgDir = Join-Path $Root 'packages'
$Work = Join-Path $env:TEMP 'driver_mirror_phase1'
Remove-Item $Work -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $PkgDir, $Work | Out-Null

function Write-SourceTxt {
    param(
        [string]$Path,
        [string]$Title,
        [string]$Version = '',
        [string]$UpdateId = '',
        [string]$SourceUrl = '',
        [string[]]$HardwareIds = @()
    )
    $lines = @("Title: $Title")
    if ($Version) { $lines += "Version: $Version" }
    if ($UpdateId) { $lines += "Microsoft Update Catalog UpdateId: $UpdateId" }
    if ($SourceUrl) { $lines += $SourceUrl }
    foreach ($id in $HardwareIds) { $lines += "Hardware ID: $id" }
    Set-Content -Path $Path -Value ($lines -join "`r`n") -Encoding UTF8
}

function New-FlatZip {
    param(
        [string]$SourceDir,
        [string]$ZipPath,
        [string]$SourceTxtPath
    )
    if ($SourceTxtPath -and (Test-Path $SourceTxtPath)) {
        Copy-Item $SourceTxtPath (Join-Path $SourceDir 'source.txt') -Force
    }
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
    $items = Get-ChildItem $SourceDir -Force
    if (-not $items) { throw "Empty source dir: $SourceDir" }
    Compress-Archive -Path (Join-Path $SourceDir '*') -DestinationPath $ZipPath -Force
}

function Expand-CabToDir {
    param([string]$CabPath, [string]$DestDir)
    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
    $proc = Start-Process -FilePath 'expand.exe' -ArgumentList @($CabPath, '-F:*', $DestDir) -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) { throw "expand.exe failed for $CabPath (exit $($proc.ExitCode))" }
}

function Get-CatalogCabUrl {
    param([string]$UpdateId)
    $base = 'https://www.catalog.update.microsoft.com/'
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    foreach ($path in @('Home.aspx', "Search.aspx?q=$UpdateId", "ScopedViewInline.aspx?updateid=$UpdateId")) {
        Invoke-WebRequest -Uri ($base + $path) -WebSession $session -Headers @{ 'User-Agent' = $ua } -UseBasicParsing | Out-Null
    }
    $payload = ConvertTo-Json -Compress -InputObject @(@{ size = 0; updateID = $UpdateId; uidInfo = $UpdateId })
    $body = ('updateIDs=' + [uri]::EscapeDataString($payload) + '&updateIDsBlocked=')
    $resp = Invoke-WebRequest -Uri ($base + 'DownloadDialog.aspx') -Method POST -Body $body -ContentType 'application/x-www-form-urlencoded' -WebSession $session -Headers @{ 'User-Agent' = $ua; 'Referer' = ($base + 'Search.aspx') } -UseBasicParsing
    $html = $resp.Content
    $m = [regex]::Match($html, "downloadInformation\[0\]\.files\[0\]\.url\s*=\s*'([^']+)'")
    if ($m.Success) { return $m.Groups[1].Value }
    $m2 = [regex]::Match($html, 'https://catalog\.s\.download\.windowsupdate\.com[^''"\s>]+')
    if ($m2.Success) { return $m2.Value }
    return $null
}

function Build-FromCab {
    param(
        [string]$CabUrl,
        [string]$ZipName,
        [string]$Title,
        [string]$Version,
        [string]$UpdateId = '',
        [string[]]$HardwareIds = @()
    )
    $stage = Join-Path $Work $ZipName
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    $cab = Join-Path $Work ($ZipName + '.cab')
    Write-Host "Downloading $Title ..."
    Invoke-WebRequest -Uri $CabUrl -OutFile $cab -UseBasicParsing -TimeoutSec 600
    Expand-CabToDir -CabPath $cab -DestDir $stage
    $srcTxt = Join-Path $Work ($ZipName + '-source.txt')
    Write-SourceTxt -Path $srcTxt -Title $Title -Version $Version -UpdateId $UpdateId -SourceUrl $CabUrl -HardwareIds $HardwareIds
    New-FlatZip -SourceDir $stage -ZipPath (Join-Path $PkgDir $ZipName) -SourceTxtPath $srcTxt
}

function Build-FromPnP {
    param(
        [string]$PublishedInf,
        [string]$ZipName,
        [string]$Title,
        [string]$Version,
        [string]$UpdateId = '',
        [string[]]$HardwareIds = @()
    )
    $stage = Join-Path $Work $ZipName
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Write-Host "Exporting $Title from $PublishedInf ..."
    pnputil /export-driver $PublishedInf $stage | Out-Null
    $files = Get-ChildItem $stage -Recurse -File
    if (-not $files) { throw "pnputil export empty for $PublishedInf" }
    $flat = Join-Path $Work ($ZipName + '-flat')
    Remove-Item $flat -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $flat | Out-Null
    foreach ($f in $files) { Copy-Item $f.FullName (Join-Path $flat $f.Name) -Force }
    $srcTxt = Join-Path $Work ($ZipName + '-source.txt')
    Write-SourceTxt -Path $srcTxt -Title $Title -Version $Version -UpdateId $UpdateId -HardwareIds $HardwareIds
    New-FlatZip -SourceDir $flat -ZipPath (Join-Path $PkgDir $ZipName) -SourceTxtPath $srcTxt
}

Write-Host '=== Phase 1 package build ==='

$wifiCab = 'https://github.com/FirstEverTech/Universal-Intel-WiFi-BT-Updater/releases/download/archive-wifi/intel_wifi_24.40.0.4.cab'
$hwidsWifi = @('PCI\VEN_8086&DEV_2723', 'PCI\VEN_8086&DEV_51F0', 'PCI\VEN_8086&DEV_7A70', 'PCI\VEN_8086&DEV_54F0', 'PCI\VEN_8086&DEV_7740')
Build-FromCab -CabUrl $wifiCab -ZipName 'intel_wifi.zip' -Title 'Intel WiFi AX/AC' -Version '24.40.0.4' -HardwareIds $hwidsWifi

$hwidsMei = @('PCI\VEN_8086&DEV_43E0', 'PCI\VEN_8086&DEV_A0EB')
Build-FromPnP -PublishedInf 'oem0.inf' -ZipName 'intel_mei.zip' -Title 'Intel MEI' -Version '2406.5.5.0' -UpdateId 'd2418c67-abd8-46cb-8b66-d91d952119e0' -HardwareIds $hwidsMei

$hwidsLan = @('PCI\VEN_10EC&DEV_8168', 'PCI\VEN_10EC&DEV_8125')
Build-FromPnP -PublishedInf 'oem8.inf' -ZipName 'realtek_lan.zip' -Title 'Realtek GbE LAN' -Version '10.79.50.1003' -UpdateId '598bb759-15e7-4cb8-990f-6f3c186e0184' -HardwareIds $hwidsLan

$audioUrl = Get-CatalogCabUrl -UpdateId 'c4d56f3c-733d-4ffb-9143-77723ac72f1c'
if ($audioUrl) {
    $hwidsAudio = @('HDAUDIO\FUNC_01&VEN_10EC&DEV_0897', 'HDAUDIO\FUNC_01&VEN_10EC&DEV_0269')
    Build-FromCab -CabUrl $audioUrl -ZipName 'realtek_audio.zip' -Title 'Realtek HD Audio' -Version '6.0.9679.1' -UpdateId 'c4d56f3c-733d-4ffb-9143-77723ac72f1c' -HardwareIds $hwidsAudio
} else {
    Write-Warning 'Catalog download failed for Realtek Audio; skipping realtek_audio.zip'
}

Write-Host 'Downloading Intel RST/VMD drivers ...'
$rstZipball = Join-Path $Work 'irst.zip'
Invoke-WebRequest -Uri 'https://github.com/arakium/IRST-VMD-Drivers/zipball/v1.0.0' -OutFile $rstZipball -UseBasicParsing -TimeoutSec 300
$rstExtract = Join-Path $Work 'irst_src'
Expand-Archive -Path $rstZipball -DestinationPath $rstExtract -Force
$rstFolder = $null
foreach ($dir in Get-ChildItem $rstExtract -Directory) {
    foreach ($name in @('IRST_12-15G', 'IRST_12-13G', 'IRST_10-11G')) {
        $candidate = Join-Path $dir.FullName $name
        if (Test-Path $candidate) { $rstFolder = $candidate; break }
    }
    if ($rstFolder) { break }
}
if (-not $rstFolder) { throw 'Could not locate IRST driver folder in zipball' }
$rstStage = Join-Path $Work 'intel_rst'
Remove-Item $rstStage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $rstStage | Out-Null
Get-ChildItem $rstFolder -Recurse -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $rstStage $_.Name) -Force }
$rstSrc = Join-Path $Work 'intel_rst-source.txt'
$hwidsRst = @('PCI\VEN_8086&DEV_09AB', 'PCI\VEN_8086&DEV_467F', 'PCI\VEN_8086&DEV_A77F', 'PCI\VEN_8086&DEV_7D0B')
Write-SourceTxt -Path $rstSrc -Title 'Intel RST/VMD' -Version '20.x' -SourceUrl 'https://github.com/arakium/IRST-VMD-Drivers' -HardwareIds $hwidsRst
New-FlatZip -SourceDir $rstStage -ZipPath (Join-Path $PkgDir 'intel_rst.zip') -SourceTxtPath $rstSrc

Write-Host ''
Write-Host '=== SHA256 ==='
Get-ChildItem $PkgDir -Filter '*.zip' | Sort-Object Name | ForEach-Object {
    $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
    Write-Output ($_.Name + "`t" + $hash)
}
