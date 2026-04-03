param(
    [Parameter(Position = 0)]
    [string]$Target,
    [Parameter()]
    [switch]$Single
)
function Get-Aes128Key {
    param([string]$Password, [byte[]]$Salt, [int]$Iterations = 100)
    $passwordBytes = [System.Text.Encoding]::UTF8.GetBytes($Password)
    $pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($passwordBytes, $Salt, $Iterations)
    return $pbkdf2.GetBytes(16)
}

function Decrypt-ES3 {
    param([byte[]]$Data, [string]$Password)
    if ($null -eq $Data -or $Data.Length -lt 16) { return $null }
    $salt = $Data[0..15]
    $encryptedData = $Data[16..($Data.Length - 1)]
    $key = Get-Aes128Key -Password $Password -Salt $salt
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key = $key
    $aes.IV = $salt
    try {
        $decryptor = $aes.CreateDecryptor()
        $decryptedBytes = $decryptor.TransformFinalBlock($encryptedData, 0, $encryptedData.Length)
        return [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
    }
    catch { return $null } finally { $aes.Dispose() }
}

function Get-RepoSaveInfo {
    param([string]$Path)
    $password = "Why would you want to cheat?... :o It's no fun. :') :'D"
    if (-not (Test-Path $Path)) { return $null }
    try {
        $content = [System.IO.File]::ReadAllBytes($Path)
        $json = (Decrypt-ES3 -Data $content -Password $password) | ConvertFrom-Json
        $playerNames = if ($null -ne $json.playerNames.value) {
            foreach ($p in $json.playerNames.value.PSObject.Properties) { $p.Value }
        }
        else { @("Unknown/Solo") }
        $stats = $json.dictionaryOfDictionaries.value.runStats
        $level = if ($null -ne $stats.level) { $stats.level } else { $stats.'save level' }
        return [PSCustomObject]@{
            Level   = if ($null -eq $level) { "N/A" } else { $level }
            Players = $playerNames -join ", "
        }
    }
    catch { return $null }
}

$savesRoot = Join-Path $HOME "AppData\LocalLow\semiwork\Repo\saves"
$saves = Get-ChildItem -Path $savesRoot -Directory
$saveNames = $saves.Name

if ($saveNames.Count -eq 0) {
    Write-Host "No save folders found in $savesRoot" -ForegroundColor Red
    return
}

$selectedFolder = $null

# Try to use command line argument if provided
if (-not [string]::IsNullOrWhiteSpace($Target)) {
    if ($Target -match '^\d+$') {
        $index = [int]$Target
        if ($index -ge 0 -and $index -lt $saveNames.Count) {
            $selectedFolder = $saveNames[$index]
        }
    }
    else {
        if ($saveNames -contains $Target) {
            $selectedFolder = $Target
        }
    }
    
    if (-not $selectedFolder) {
        Write-Host "Target '$Target' not found as an index or folder name." -ForegroundColor Yellow
    }
}

# Fallback to interactive selection if no valid target was provided
if (-not $selectedFolder) {
    Write-Host "Available folders in Repo saves:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $saveNames.Count; $i++) {
        $saveName = $saveNames[$i]
        # REPO save files are usually inside the folder matching the folder name
        $es3Path = Join-Path $savesRoot "$saveName\$saveName.es3"
        
        $info = Get-RepoSaveInfo -Path $es3Path
        if ($info) {
            Write-Host "[$i] Level: $($info.Level) | Players: $($info.Players) | Folder: $saveName"
        }
        else {
            Write-Host "[$i] $saveName"
        }
    }

    $choice = Read-Host "Select a folder to backup (Enter number or name, default is 0)"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "0" }

    if ($choice -match '^\d+$') {
        $index = [int]$choice
        if ($index -ge 0 -and $index -lt $saveNames.Count) {
            $selectedFolder = $saveNames[$index]
        }
    }
    else {
        if ($saveNames -contains $choice) {
            $selectedFolder = $choice
        }
    }

    if (-not $selectedFolder) {
        Write-Host "Invalid selection." -ForegroundColor Red
        return
    }
}

$source = Join-Path $savesRoot "$selectedFolder\*"
$backupPath = Join-Path $PSScriptRoot "Repo Saves"
if (-not (Test-Path -Path $backupPath)) {
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
}
$destination = Join-Path $backupPath $selectedFolder

if (-not (Test-Path -Path $destination)) {
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
}

if (-not $Single) {
    Write-Host "Auto-backup mode enabled! Backing up '$selectedFolder' every 1 minute..." -ForegroundColor Green
    Write-Host "Press Ctrl+C to stop." -ForegroundColor White
    
    while ($true) {
        $timestamp = Get-Date -Format "HH:mm:ss"
        
        # Check if the source folder still exists
        $actualSource = Join-Path $savesRoot $selectedFolder
        if (-not (Test-Path -Path $actualSource)) {
            Write-Host "[$timestamp] WARNING: Source folder '$selectedFolder' disappeared! Attempting automatic recovery..." -ForegroundColor Yellow
            
            try {
                # Source for restoration is our current backup folder
                $restoreSource = $destination
                
                if (Test-Path -Path $restoreSource) {
                    New-Item -ItemType Directory -Path $actualSource -Force | Out-Null
                    Copy-Item -Path "$restoreSource\*" -Destination $actualSource -Recurse -Force -ErrorAction Stop
                    Write-Host "[$timestamp] RECOVERY SUCCESSFUL: Folder restored from backup." -ForegroundColor Green
                }
                else {
                    Write-Host "[$timestamp] RECOVERY FAILED: No backup found to restore from." -ForegroundColor Red
                    return
                }
            }
            catch {
                Write-Host "[$timestamp] RECOVERY FAILED: $($_.Exception.Message)" -ForegroundColor Red
                return
            }
        }

        Copy-Item -Path $source -Destination $destination -Recurse -Force
        Write-Host "[$timestamp] Auto-backup complete!" -ForegroundColor Gray
        Start-Sleep -Seconds 60
    }
}
else {
    Copy-Item -Path $source -Destination $destination -Recurse -Force
    Write-Host "Backup complete! Folder contents copied to $destination" -ForegroundColor Green
}
