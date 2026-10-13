param(
    [string]$LogDir  = "$HOME\Desktop\log",
    [int]$MinFiles   = 10,
    [int]$MaxFiles   = 50,
    [int]$MinSizeKB  = 5,
    [int]$MaxSizeKB  = 50,
    [int]$MaxDaysOld = 30,
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

# Optional: wipe the folder before generating
if ($Clean -and (Test-Path $LogDir)) {
    Write-Host "Removing existing folder: $LogDir" -ForegroundColor Yellow
    Remove-Item -Path $LogDir -Recurse -Force
}

# Create the log folder if it does not exist
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    Write-Host "Created folder: $LogDir" -ForegroundColor Green
}

# Random number of files in [MinFiles, MaxFiles]
$fileCount = Get-Random -Minimum $MinFiles -Maximum ($MaxFiles + 1)

Write-Host "Generating $fileCount files in $LogDir ..." -ForegroundColor Cyan

# Generate the files
for ($i = 1; $i -le $fileCount; $i++) {
    $fileName = "log_$i.txt"
    $filePath = Join-Path $LogDir $fileName

    # Random size in KB -> bytes
    $sizeKB    = Get-Random -Minimum $MinSizeKB -Maximum $MaxSizeKB
    $sizeBytes = $sizeKB * 1KB

    # Write random bytes
    $bytes = New-Object byte[] $sizeBytes
    (New-Object Random).NextBytes($bytes)
    [IO.File]::WriteAllBytes($filePath, $bytes)

    # Random modification date: from 1 to MaxDaysOld days ago
    $daysAgo = Get-Random -Minimum 1 -Maximum ($MaxDaysOld + 1)
    (Get-Item $filePath).LastWriteTime = (Get-Date).AddDays(-$daysAgo)
}

# Summary
$files     = Get-ChildItem -Path $LogDir -File
$totalSize = ($files | Measure-Object -Property Length -Sum).Sum

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "  Files created: $($files.Count)"
Write-Host "  Total size:    $([math]::Round($totalSize / 1KB, 2)) KB"
Write-Host "  Folder:        $LogDir"