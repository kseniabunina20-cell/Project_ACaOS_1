$ErrorActionPreference = "Stop"

$BaseDir = "$HOME\Desktop\test_archive"
if (Test-Path $BaseDir) {
    Remove-Item $BaseDir -Recurse -Force
}
New-Item -ItemType Directory -Path $BaseDir | Out-Null

$LogDir    = Join-Path $BaseDir "log"
$BackupDir = Join-Path $BaseDir "backup"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

# Параметры тестов
$ThresholdMB = 1
$MaxFilesToArchive = 10

function Write-Status {
    param([string]$Message, [ConsoleColor]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

# Test 1: порог не превышен
Write-Status "[TEST 1] Generating low-volume logs..." "Yellow"
for ($i = 1; $i -le 15; $i++) {
    $path = Join-Path $LogDir "log_$i.txt"
    $size = (Get-Random -Minimum 5 -Maximum 10) * 1KB
    [IO.File]::WriteAllBytes($path, [byte[]]::new($size))
    (Get-Item $path).LastWriteTime = (Get-Date).AddDays(-(Get-Random -Minimum 1 -Maximum 31))
}

$files = Get-ChildItem $LogDir -File
$totalSize = ($files | Measure-Object -Property Length -Sum).Sum
$percent = [math]::Round(($totalSize / ($ThresholdMB * 1MB)) * 100, 2)

if ($percent -le 80) {
    Write-Status "[OK] Test 1 passed: no archive needed ($percent%)" "Green"
} else {
    Write-Status "[FAIL] Test 1: archive created unexpectedly" "Red"
}

# Test 2: порог превышен
Write-Status "[TEST 2] Generating high-volume logs..." "Yellow"
Remove-Item $LogDir -Recurse -Force
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
for ($i = 1; $i -le 30; $i++) {
    $path = Join-Path $LogDir "log_$i.txt"
    $size = (Get-Random -Minimum 20 -Maximum 60) * 1KB
    [IO.File]::WriteAllBytes($path, [byte[]]::new($size))
    (Get-Item $path).LastWriteTime = (Get-Date).AddDays(-(Get-Random -Minimum 1 -Maximum 31))
}

$beforeCount = (Get-ChildItem $LogDir -File).Count
$files = Get-ChildItem $LogDir -File
$totalSize = ($files | Measure-Object -Property Length -Sum).Sum
$percent = [math]::Round(($totalSize / ($ThresholdMB * 1MB)) * 100, 2)

if ($percent -gt 80) {
    $oldFiles = $files | Sort-Object LastWriteTime | Select-Object -First $MaxFilesToArchive
    $name = "logs_$(Get-Date -Format 'yyyyMMdd_HHmmss').tar.gz"
    $archive = Join-Path $BackupDir $name
    $names = $oldFiles | ForEach-Object { $_.Name }


    if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)) {
        Write-Status "[FAIL] Test 2: tar.exe not found. Install tar and ensure it is in PATH." "Red"
    } else {
        & tar.exe -czf $archive -C $LogDir $names
        if ($LASTEXITCODE -eq 0) {
            $oldFiles | Remove-Item -Force
            $afterCount = (Get-ChildItem $LogDir -File -ErrorAction SilentlyContinue).Count
            if ($afterCount -lt $beforeCount -and (Test-Path $archive)) {
                Write-Status "[OK] Test 2 passed: archive created, files removed" "Green"
            } else {
                Write-Status "[FAIL] Test 2: archive or file count check failed" "Red"
            }
        } else {
            Write-Status "[FAIL] Test 2: tar.exe error (exit code $LASTEXITCODE)" "Red"
        }
    }
} else {
    Write-Status "[FAIL] Test 2: threshold not exceeded as expected ($percent%)" "Red"
}


Write-Status "[TEST 3] Checking missing folder..." "Yellow"
$fakeDir = Join-Path $BaseDir "missing"
if (-not (Test-Path $fakeDir)) {
    Write-Status "[OK] Test 3 passed: folder not found" "Green"
} else {
    Write-Status "[FAIL] Test 3: folder unexpectedly exists" "Red"
}

Remove-Item $BaseDir -Recurse -Force
Write-Status "Tests completed. Data left in $BaseDir for inspection." "Cyan"
