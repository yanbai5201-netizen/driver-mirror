# Upload driver zips to GitHub Release using git credential token
$ErrorActionPreference = 'Stop'
$Repo = 'yanbai5201-netizen/driver-mirror'
$Tag = 'v2026.05.29'
$Title = 'v2026.05.29'
$Notes = 'Phase 1: 8 seed packages for common Intel/Realtek laptops.'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Assets = @(
    'intel_chipset.zip', 'intel_serialio.zip', 'intel_bluetooth.zip',
    'intel_wifi.zip', 'intel_mei.zip', 'intel_rst.zip',
    'realtek_lan.zip', 'realtek_audio.zip'
) | ForEach-Object { Join-Path $Root "packages\$_" }

function Get-GitHubToken {
    $inputText = "protocol=https`nhost=github.com`n`n"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'git'
    $psi.Arguments = 'credential fill'
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $p = [Diagnostics.Process]::Start($psi)
    $p.StandardInput.Write($inputText)
    $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) { throw "git credential fill failed: $err" }
    foreach ($line in $out -split "`r?`n") {
        if ($line -like 'password=*') { return $line.Substring(9).Trim() }
    }
    throw 'Cannot read GitHub token from git credential. Run: gh auth login'
}

function Invoke-GitHubJson {
    param([string]$Method, [string]$Url, [string]$Token, [string]$JsonBody = $null)
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Method = $Method
    $req.UserAgent = 'driver-mirror-uploader'
    $req.Accept = 'application/vnd.github+json'
    $req.Headers.Add('Authorization', "Bearer $Token")
    if ($JsonBody) {
        $bytes = [Text.Encoding]::UTF8.GetBytes($JsonBody)
        $req.ContentType = 'application/json'
        $req.ContentLength = $bytes.Length
        $stream = $req.GetRequestStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Close()
    }
    try {
        $resp = $req.GetResponse()
        $reader = New-Object IO.StreamReader($resp.GetResponseStream())
        $text = $reader.ReadToEnd()
        $reader.Close()
        return $text
    } catch [System.Net.WebException] {
        $resp = $_.Exception.Response
        if ($resp -and $resp.StatusCode.value__ -eq 404) { return $null }
        if ($resp) {
            $reader = New-Object IO.StreamReader($resp.GetResponseStream())
            $detail = $reader.ReadToEnd()
            $reader.Close()
            throw "GitHub API $Method $Url failed: $detail"
        }
        throw
    }
}

function Upload-ReleaseAsset {
    param([string]$UploadUrlTemplate, [string]$Token, [string]$AssetPath)
    $name = [uri]::EscapeDataString((Split-Path $AssetPath -Leaf))
    $url = $UploadUrlTemplate -replace '\{\?name,label\}', "?name=$name"
    $data = [IO.File]::ReadAllBytes($AssetPath)
    $req = [System.Net.HttpWebRequest]::Create($url)
    $req.Method = 'POST'
    $req.UserAgent = 'driver-mirror-uploader'
    $req.Accept = 'application/vnd.github+json'
    $req.Headers.Add('Authorization', "Bearer $Token")
    $req.ContentType = 'application/octet-stream'
    $req.ContentLength = $data.Length
    $stream = $req.GetRequestStream()
    $stream.Write($data, 0, $data.Length)
    $stream.Close()
    $resp = $req.GetResponse()
    $resp.Close()
}

foreach ($asset in $Assets) {
    if (-not (Test-Path $asset)) { throw "Missing asset: $asset" }
}

$token = Get-GitHubToken
$releaseJson = Invoke-GitHubJson -Method GET -Url "https://api.github.com/repos/$Repo/releases/tags/$Tag" -Token $token
if (-not $releaseJson) {
    Write-Host 'Creating release...'
    $payload = (@{
        tag_name = $Tag
        name = $Title
        body = $Notes
        draft = $false
        prerelease = $false
    } | ConvertTo-Json -Compress)
    $releaseJson = Invoke-GitHubJson -Method POST -Url "https://api.github.com/repos/$Repo/releases" -Token $token -JsonBody $payload
}
$release = $releaseJson | ConvertFrom-Json
$uploadUrl = [string]$release.upload_url
if (-not $uploadUrl) { throw 'Missing upload_url from release' }
$existing = @{}
foreach ($a in $release.assets) { $existing[$a.name] = $true }

foreach ($assetPath in $Assets) {
    $name = Split-Path $assetPath -Leaf
    if ($existing.ContainsKey($name)) {
        Write-Host "Skip (exists): $name"
        continue
    }
    $kb = [math]::Round((Get-Item $assetPath).Length / 1KB)
    Write-Host "Uploading $name ($kb KB) ..."
    Upload-ReleaseAsset -UploadUrlTemplate $uploadUrl -Token $token -AssetPath $assetPath
    Write-Host "Uploaded $name"
}

Write-Host "Done: $($release.html_url)"
