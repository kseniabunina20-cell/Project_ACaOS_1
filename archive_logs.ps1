param(
    [string]$LogDir    = "$HOME\Desktop\log",
    [int]$Threshold    = 80,
    [int]$FileCount    = 10,
    [int]$MaxSizeMB    = 100,
    [string]$BackupDir = "$HOME\Desktop\backup"
)

# Останавливаться при любой ошибке
$ErrorActionPreference = "Stop"

# 1. Проверяем, что папка с логами существует
if (-not (Test-Path $LogDir)) {
    Write-Host "Папка не найдена: $LogDir" -ForegroundColor Red
    exit 1
}

# 2. Создаём папку для архивов, если её нет
if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir | Out-Null
}

# 3. Считаем размер всех файлов в папке
$files = Get-ChildItem -Path $LogDir -File
if ($files.Count -eq 0) {
    Write-Host "Папка пуста: $LogDir" -ForegroundColor Yellow
    exit 0
}

$totalSize = ($files | Measure-Object -Property Length -Sum).Sum

# 4. Считаем процент заполнения
#    MaxSizeMB — это «размер папки», от которого считаем процент
$maxSize = $MaxSizeMB * 1MB
$percent = [math]::Round(($totalSize / $maxSize) * 100, 2)

Write-Host "Заполнение: $percent % (порог: $Threshold %)"

# 5. Если процент ниже порога — выходим
if ($percent -le $Threshold) {
    Write-Host "Порог не превышен, архивация не нужна." -ForegroundColor Green
    exit 0
}

# 6. Берём FileCount самых старых файлов
$oldFiles = $files | Sort-Object LastWriteTime | Select-Object -First $FileCount

# 7. Формируем имя архива и путь к нему
$name = "logs_$(Get-Date -Format 'yyyyMMdd_HHmmss').tar.gz"
$archive = Join-Path $BackupDir $name

# 8. Собираем имена файлов в массив
$names = $oldFiles | ForEach-Object { $_.Name }

# 9. Запускаем tar для создания архива
#    -C переходит в папку с логами, чтобы внутри архива были только имена файлов
tar.exe -czf $archive -C $LogDir $names

# 10. Проверяем результат
if ($LASTEXITCODE -eq 0) {
    Write-Host "Архив создан: $archive" -ForegroundColor Green
} else {
    Write-Host "Ошибка tar.exe, код $LASTEXITCODE" -ForegroundColor Red
    exit 1
}