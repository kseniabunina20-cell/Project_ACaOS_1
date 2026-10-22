#!/bin/bash
# Использование: sudo ./test_backup.sh [размер_папки_MB] [заполнение_%] [мин_файлов] [макс_файлов]
# Пример:        sudo ./test_backup.sh 50 70 10 40

SCRIPT="$(dirname "$(readlink -f "$0")")/laba1.sh"

SIZE_MB="${1:-50}"       # размер папки (отдельная ФС tmpfs)
FILL_PCT="${2:-70}"      # на сколько % заполнить
MIN_FILES="${3:-10}"
MAX_FILES="${4:-40}"

if [ "$EUID" -ne 0 ]; then
    echo "Нужен root для mount (запустите через sudo)"
    exit 1
fi

WORK=$(mktemp -d)
LOG_DIR="$WORK/log"
BACKUP_DIR="$WORK/backup"
mkdir -p "$LOG_DIR"

PASS=0
FAIL=0

cleanup() {
    umount "$LOG_DIR" 2>/dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT

check() {  # check "описание" код_возврата
    if [ "$2" -eq 0 ]; then
        echo "  [PASS] $1"; PASS=$((PASS+1))
    else
        echo "  [FAIL] $1"; FAIL=$((FAIL+1))
    fi
}

# ---------- подготовка папки заданного размера ----------
mount -t tmpfs -o size="${SIZE_MB}M" tmpfs "$LOG_DIR" || { echo "mount не удался"; exit 1; }

N_FILES=$((MIN_FILES + RANDOM % (MAX_FILES - MIN_FILES + 1)))
TOTAL_BYTES=$((SIZE_MB * 1024 * 1024 * FILL_PCT / 100))
AVG=$((TOTAL_BYTES / N_FILES))

echo "Размер папки: ${SIZE_MB} MB, заполнение: ~${FILL_PCT}%, файлов: $N_FILES"

for i in $(seq 1 "$N_FILES"); do
    SZ=$((AVG * (50 + RANDOM % 100) / 100))            # случайный размер 0.5..1.5 от среднего
    [ "$SZ" -lt 1 ] && SZ=1
    head -c "$SZ" /dev/zero > "$LOG_DIR/app_$i.log"
    touch -d "$((N_FILES - i + 1)) days ago" "$LOG_DIR/app_$i.log"   # app_1.log - самый старый
done

# файлы, которые фильтр должен пропустить
echo "text"  > "$LOG_DIR/notes.txt"
echo "old"   > "$LOG_DIR/old_archive.gz"
touch -d "100 days ago" "$LOG_DIR/notes.txt" "$LOG_DIR/old_archive.gz"
: > "$LOG_DIR/empty.log"
touch -d "100 days ago" "$LOG_DIR/empty.log"

USAGE=$(df -P "$LOG_DIR" | tail -1 | awk '{print $5}' | tr -d '%')
echo "Фактическая заполненность: $USAGE%"
echo

M=5
[ "$M" -gt "$N_FILES" ] && M=$N_FILES

# ---------- тест-кейсы ----------
echo "Тест 1: без аргументов -> код 1"
"$SCRIPT" >/dev/null 2>&1
check "код возврата 1" $([ $? -eq 1 ]; echo $?)

echo "Тест 2: несуществующая папка -> код 1"
"$SCRIPT" /no/such/dir 50 5 "$BACKUP_DIR" >/dev/null 2>&1
check "код возврата 1" $([ $? -eq 1 ]; echo $?)

echo "Тест 3: нечисловой порог -> код 1"
"$SCRIPT" "$LOG_DIR" abc 5 "$BACKUP_DIR" >/dev/null 2>&1
check "код возврата 1" $([ $? -eq 1 ]; echo $?)

echo "Тест 4: порог выше заполненности -> архива нет"
rm -rf "$BACKUP_DIR"
"$SCRIPT" "$LOG_DIR" $((USAGE + 5)) "$M" "$BACKUP_DIR" >/dev/null 2>&1
check "код возврата 0" $([ $? -eq 0 ]; echo $?)
check "папка backup создана" $([ -d "$BACKUP_DIR" ]; echo $?)
check "архивов нет" $([ -z "$(ls -A "$BACKUP_DIR")" ]; echo $?)

echo "Тест 5: порог ниже заполненности -> архив создан"
"$SCRIPT" "$LOG_DIR" $((USAGE - 5)) "$M" "$BACKUP_DIR" >/dev/null 2>&1
check "код возврата 0" $([ $? -eq 0 ]; echo $?)
ARCH=$(ls "$BACKUP_DIR"/log_backup_*.tar.gz 2>/dev/null | head -1)
check "архив существует" $([ -n "$ARCH" ]; echo $?)
check "архив валиден (tar -tzf)" $(tar -tzf "$ARCH" >/dev/null 2>&1; echo $?)

echo "Тест 6: в архиве ровно M файлов"
CNT=$(tar -tzf "$ARCH" 2>/dev/null | wc -l)
check "файлов в архиве: $CNT, ожидалось: $M" $([ "$CNT" -eq "$M" ]; echo $?)

echo "Тест 7: в архиве именно самые старые файлы"
OK=0
for i in $(seq 1 "$M"); do
    tar -tzf "$ARCH" | grep -q "app_$i.log$" || OK=1
done
check "app_1.log .. app_$M.log в архиве" $OK

echo "Тест 8: фильтрация (txt, gz, пустые не попали)"
tar -tzf "$ARCH" | grep -qE 'notes.txt|old_archive.gz|empty.log'
check "лишних файлов в архиве нет" $([ $? -ne 0 ]; echo $?)

echo "Тест 9: M больше числа подходящих файлов -> архивируются все подходящие"
rm -f "$BACKUP_DIR"/*
sleep 1
"$SCRIPT" "$LOG_DIR" $((USAGE - 5)) 9999 "$BACKUP_DIR" >/dev/null 2>&1
ARCH=$(ls "$BACKUP_DIR"/log_backup_*.tar.gz 2>/dev/null | head -1)
CNT=$(tar -tzf "$ARCH" 2>/dev/null | wc -l)
check "файлов в архиве: $CNT, ожидалось: $N_FILES" $([ "$CNT" -eq "$N_FILES" ]; echo $?)

echo "Тест 10: папка без подходящих файлов"
rm -f "$LOG_DIR"/*.log "$BACKUP_DIR"/*
echo "x" > "$LOG_DIR/filler.txt"   # занять место, чтобы USAGE > 0
OUT=$("$SCRIPT" "$LOG_DIR" 0 5 "$BACKUP_DIR" 2>&1)
RC=$?
check "код возврата 0" $([ "$RC" -eq 0 ]; echo $?)
check "сообщение 'Нет файлов для архивации'" $(echo "$OUT" | grep -q "Нет файлов для архивации"; echo $?)
check "архив не создан" $([ -z "$(ls -A "$BACKUP_DIR")" ]; echo $?)

echo
echo "Итого: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
