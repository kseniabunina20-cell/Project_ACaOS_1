param(
    [string]$ScriptPath = ".\backup_logs.ps1",
    [switch]$KeepData
)

$ErrorActionPreference = "Stop"


function Log-Pass { param([string]$msg) Write-Host "PASS: $msg" -ForegroundColor Green }
function Log-Fail { param([string]$msg) Write-Host "FAIL: $msg" -ForegroundColor Red; exit 1 }


$TestLogDir  = "$env:TEMP\test_log"
$TestBackupDir = "$env:TEMP\test_backup"

function Cleanup {
    if (Test-Path $TestLogDir)  { Remove-Item -Recurse -Force $TestLogDir }
    if (Test-Path $TestBackupDir) { Remove-Item -Recurse -Force $TestBackupDir }
}

if (-not $KeepData) { Cleanup }
New-Item -ItemType Directory -Path $TestLogDir -Force | Out-Null
New-Item -ItemType Directory -Path $TestBackupDir -Force | Out-Null

Write-Host "=== Запуск тестов для $ScriptPath ==="


Write-Host "[Тест 1] Проверка обработки несуществующей папки логов..."
$result = & $ScriptPath -LogDir "$env:TEMP\nonexistent_folder" -Threshold 80 -FileCount 10 -MaxSizeMB 100 -BackupDir $TestBackupDir 2>&1
if ($LASTEXITCODE -eq 1 -and $result -match "Папка не найдена") {
    Log-Pass "Корректная обработка несуществующей папки"
} else {
    Log-Fail "Неверная реакция на несуществующую папку (код: $LASTEXITCODE, вывод: $result)"
}


Write-Host "[Тест 2] Проверка автоматического создания папки backup..."
$backupPath = "$env:TEMP\ps_test_backup_new"
if (Test-Path $backupPath) { Remove-Item -Recurse -Force $backupPath }

& $ScriptPath -LogDir $TestLogDir -Threshold 99 -FileCount 5 -MaxSizeMB 100 -BackupDir $backupPath 2>&1 | Out-Null
if (Test-Path $backupPath -PathType Container) {
    Log-Pass "Папка backup успешно создана"
    Remove-Item -Recurse -Force $backupPath
} else {
    Log-Fail "Папка backup не была создана"
}


Write-Host "[Тест 3] Проверка отсутствия архивации при нормальном уровне заполнения..."

$smallFile = New-Item -Path "$TestLogDir\tiny.log" -ItemType File -Force

& $ScriptPath -LogDir $TestLogDir -Threshold 90 -FileCount 5 -MaxSizeMB 100 -BackupDir $TestBackupDir 2>&1 | Out-Null
$archives = Get-ChildItem -Path $TestBackupDir -Filter "*.tar.gz" -File
if ($archives.Count -eq 0) {
    Log-Pass "Архивация не произведена, так как порог не превышен"
} else {
    Log-Fail "Архив создан ошибочно (найдено: $($archives.Count))"
}


Write-Host "[Тест 4] Проверка создания архива при превышении порога..."

Remove-Item $smallFile -Force
$totalBytes = 0
for ($i = 1; $i -le 15; $i++) {
    $f = New-Item -Path "$TestLogDir\file_$i.log" -ItemType File -Force

    [System.IO.File]::WriteAllBytes($f.FullName, (New-Object byte[] (8 * 1MB)))
    $totalBytes += 8MB
}

& $ScriptPath -LogDir $TestLogDir -Threshold 80 -FileCount 10 -MaxSizeMB 100 -BackupDir $TestBackupDir 2>&1 | Out-Null

$archives = Get-ChildItem -Path $TestBackupDir -Filter "*.tar.gz" -File | Sort-Object LastWriteTime -Descending
if ($archives.Count -ge 1) {
    Log-Pass "Архив успешно создан"
} else {
    Log-Fail "Архив не был создан"
}

Write-Host "[Тест 5] Проверка фильтрации самых старых файлов..."
if ($archives.Count -lt 1) { Log-Fail "Нет архива для проверки содержимого"; exit 1 }
$archivePath = $archives[0].FullName


$oldFile  = Get-Item "$TestLogDir\old.log"
$newFile  = Get-Item "$TestLogDir\new.log"
$veryNew  = Get-Item "$TestLogDir\very_new.log"

$oldFile.LastWriteTime  = (Get-Date).AddDays(-5)
$newFile.LastWriteTime  = (Get-Date).AddDays(-1)
$veryNew.LastWriteTime = (Get-Date).AddSeconds(-10)


& $ScriptPath -LogDir $TestLogDir -Threshold 1 -FileCount 1 -MaxSizeMB 100 -BackupDir $TestBackupDir 2>&1 | Out-Null
$latestArchive = Get-ChildItem -Path $TestBackupDir -Filter "*.tar.gz" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1


$contents = tar.exe -tf $latestArchive.FullName 2>&1

$hasOld  = $contents -match "old.log"
$hasNew  = $contents -match "new.log"
$hasVeryNew = $contents -match "very_new.log"

if ($hasOld -and -not $hasNew -and -not $hasVeryNew) {
    Log-Pass "В архив попал самый старый файл, новые не затронуты"
} else {
    Log-Fail "Некорректная фильтрация файлов в архиве"
    Write-Host "Содержимое архива:" -ForegroundColor Yellow
    $contents
}


Write-Host "[Тест 6] Проверка работы, если файлов меньше, чем запрошено (FileCount)..."

Remove-Item "$TestLogDir\*" -Force -ErrorAction SilentlyContinue
$singleFile = New-Item -Path "$TestLogDir\only_one.log" -ItemType File -Force
[System.IO.File]::WriteAllBytes($singleFile.FullName, (New-Object byte[] 5MB))

& $ScriptPath -LogDir $TestLogDir -Threshold 1 -FileCount 10 -MaxSizeMB 100 -BackupDir $TestBackupDir 2>&1 | Out-Null

$archivesAfter = Get-ChildItem -Path $TestBackupDir -Filter "*.tar.gz" -File | Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-1) }
if ($archivesAfter.Count -ge 1) {
    Log-Pass "Архив создан даже при FileCount > количества файлов"
} else {
    Log-Fail "Архив не создан, когда FileCount больше количества файлов"
}

Write-Host "=== Все тесты завершены ==="
if (-not $KeepData) { Cleanup }