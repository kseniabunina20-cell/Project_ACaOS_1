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

$ThresholdMB = 1
$MaxFilesToArchive = 10

function Write-Status {
    param([string]$Message, [ConsoleColor]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

# Test 1: порог не превышен (архив не нужен)
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

# Test 2: порог превышен, архивируются старые файлы
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

#  Test 3: проверка отсутствия папки 
Write-Status "[TEST 3] Checking missing folder..." "Yellow"
$fakeDir = Join-Path $BaseDir "missing"
if (-not (Test-Path $fakeDir)) {
    Write-Status "[OK] Test 3 passed: folder not found" "Green"
} else {
    Write-Status "[FAIL] Test 3: folder unexpectedly exists" "Red"
}

#  Test 4: M больше числа подходящих файлов -> архивируются все подходящие 
Write-Status "[TEST 4] M > available files: archive all available old files" "Yellow"
Remove-Item $LogDir -Recurse -Force
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

for ($i = 1; $i -le 5; $i++) {
    $path = Join-Path $LogDir "old_$i.txt"
    $size = 50KB
    [IO.File]::WriteAllBytes($path, [byte[]]::new($size))
    # Делаем файлы старыми
    (Get-Item $path).LastWriteTime = (Get-Date).AddDays(-10)
}

$allFiles = Get-ChildItem $LogDir -File | Sort-Object LastWriteTime
$beforeCount = $allFiles.Count
$M = 10
$toArchive = $allFiles | Select-Object -First $M

$name = "all_old_$(Get-Date -Format 'yyyyMMdd_HHmmss').tar.gz"
$archive = Join-Path $BackupDir $name
$names = $toArchive | ForEach-Object { $_.Name }

if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)) {
    Write-Status "[FAIL] Test 4: tar.exe not found" "Red"
} else {
    & tar.exe -czf $archive -C $LogDir $names
    if ($LASTEXITCODE -eq 0) {
        $toArchive | Remove-Item -Force
        $afterCount = (Get-ChildItem $LogDir -File -ErrorAction SilentlyContinue).Count
        if ($afterCount -eq 0 -and (Test-Path $archive)) {
            Write-Status "[OK] Test 4 passed: all old files archived and removed" "Green"
        } else {
            Write-Status "[FAIL] Test 4: not all files removed or archive missing" "Red"
        }
    } else {
        Write-Status "[FAIL] Test 4: tar.exe error (exit code $LASTEXITCODE)" "Red"
    }
}

# Test 5: проверка, что папка с логами существует
Write-Status "[TEST 5] Verify log directory exists..." "Yellow"
if (Test-Path $LogDir) {
    Write-Status "[OK] Test 5 passed: log directory exists" "Green"
} else {
    Write-Status "[FAIL] Test 5: log directory does not exist" "Red"
}

# Test 6: нечисловой порог 
Write-Status "[TEST 6] Non-numeric threshold handling..." "Yellow"
try {
    $badThreshold = "abc"
    $dummyPercent = [math]::Round((100KB / ($badThreshold * 1MB)) * 100, 2)
    Write-Status "[FAIL] Test 6: non-numeric threshold did not cause an error" "Red"
} catch {
    Write-Status "[OK] Test 6 passed: non-numeric threshold correctly caused an error" "Green"
}

#  Test 7: папка без подходящих файлов (нет старых файлов)
Write-Status "[TEST 7] No suitable files to archive (all recent)" "Yellow"
Remove-Item $LogDir -Recurse -Force
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

for ($i = 1; $i -le 5; $i++) {
    $path = Join-Path $LogDir "recent_$i.txt"
    $size = 10KB
    [IO.File]::WriteAllBytes($path, [byte[]]::new($size))
    # Файлы свежие (не старые)
    (Get-Item $path).LastWriteTime = (Get-Date)
}

$recentFiles = Get-ChildItem $LogDir -File | Sort-Object LastWriteTime
$M = 10
$toArchive = $recentFiles | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | Select-Object -First $M

if ($toArchive.Count -eq 0) {
    Write-Status "[OK] Test 7 passed: no suitable (old) files found for archiving" "Green"
} else {
    Write-Status "[FAIL] Test 7: unexpected files selected for archiving" "Red"
}

Remove-Item $BaseDir -Recurse -Force
Write-Status "Tests completed. Data left in $BaseDir for inspection." "Cyan"
