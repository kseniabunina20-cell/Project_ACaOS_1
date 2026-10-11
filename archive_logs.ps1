param(
    [string]$LogDir    = "$HOME\Desktop\log",
    [ValidateRange(0, 100)]
    [int]$Threshold    = 80,
    [ValidateRange(1, 100000)]
    [int]$FileCount    = 10,
    [ValidateRange(1, 1000000)]
    [int]$MaxSizeMB    = 100,
    [string]$BackupDir = "$HOME\Desktop\backup"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -Path $LogDir -PathType Container)) {
    Write-Host "ERROR: folder not found: $LogDir" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}

$tarExe = Get-Command tar.exe -ErrorAction SilentlyContinue
if (-not $tarExe) {
    Write-Host "ERROR: tar.exe not found" -ForegroundColor Red
    exit 1
}

$files = @(Get-ChildItem -Path $LogDir -File -ErrorAction SilentlyContinue)
if ($files.Count -eq 0) {
    Write-Host "Folder is empty: $LogDir" -ForegroundColor Yellow
    exit 0
}

$totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
if ($null -eq $totalBytes) { $totalBytes = 0 }

$maxBytes     = [int64]$MaxSizeMB * 1MB
$usagePercent = [math]::Round(($totalBytes / $maxBytes) * 100, 2)

Write-Host "Usage: $usagePercent % (threshold: $Threshold %)"

if ($usagePercent -le $Threshold) {
    Write-Host "Below threshold. Nothing to do." -ForegroundColor Green
    exit 0
}

$oldFiles = $files | Sort-Object LastWriteTime | Select-Object -First $FileCount

$timestamp   = Get-Date -Format "yyyyMMdd_HHmmss"
$archivePath = Join-Path $BackupDir "logs_$timestamp.tar.gz"
$resolvedLogDir = (Resolve-Path $LogDir).Path
$fileNames = $oldFiles | ForEach-Object { $_.Name }

& tar.exe -czf $archivePath -C $resolvedLogDir @fileNames

if ($LASTEXITCODE -eq 0) {
    Write-Host "Archive created: $archivePath" -ForegroundColor Green
} else {
    Write-Host "tar.exe failed: $LASTEXITCODE" -ForegroundColor Red
    exit 1
}
