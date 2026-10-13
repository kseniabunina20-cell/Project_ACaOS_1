#!/usr/bin/env bash
set -euo pipefail

SCRIPT="./backup_logs.sh"  


log_pass() { echo "PASS: \$1"; }
log_fail() { echo "FAIL: \$1"; exit 1; }


TEST_LOG_DIR="/tmp/test_log_dir"
TEST_BACKUP_DIR="/tmp/test_backup_dir"

cleanup() {
  rm -rf "$TEST_LOG_DIR" "$TEST_BACKUP_DIR"
}

cleanup
mkdir -p "\$TEST_LOG_DIR"
mkdir -p "\$TEST_BACKUP_DIR"

echo "=== Запуск тестов для \$SCRIPT ==="


echo "[Тест 1] Проверка обработки неверного числа аргументов..."
if ! "\$SCRIPT" "/tmp" 80 5 2>&1 | grep -q "Использование:"; then
  log_fail "Не выводится сообщение об использовании при неверных аргументах"
else
  log_pass "Корректное сообщение об использовании"
fi

echo "[Тест 2] Проверка обработки несуществующей папки логов..."
if ! "$SCRIPT" "/nonexistent/path" 80 5 "$TEST_BACKUP_DIR" 2>&1 | grep -q "не найдена"; then
  log_fail "Не выводится ошибка при отсутствии папки логов"
else
  log_pass "Корректная обработка несуществующей папки"
fi

echo "[Тест 3] Проверка автоматического создания папки backup..."
rm -rf "\$TEST_BACKUP_DIR"
for i in {1..10}; do
  dd if=/dev/urandom of="${TEST_LOG_DIR}/file_${i}.log" bs=1M count=5 status=none
done


"$SCRIPT" "$TEST_LOG_DIR" 1 3 "\$TEST_BACKUP_DIR" > /dev/null 2>&1

if [[ ! -d "\$TEST_BACKUP_DIR" ]]; then
  log_fail "Папка backup не была создана автоматически"
else
  log_pass "Папка backup успешно создана"
fi


echo "[Тест 4] Проверка создания архива при превышении порога..."
if [[ $(find "$TEST_LOG_DIR" -type f | wc -l) -eq 0 ]]; then
  for i in {1..5}; do
    touch "${TEST_LOG_DIR}/test_${i}.log"
  done
fi


"$SCRIPT" "$TEST_LOG_DIR" 1 3 "\$TEST_BACKUP_DIR" > /dev/null 2>&1


ARCHIVE_FILE=$(find "$TEST_BACKUP_DIR" -name "log_backup_*.tar.gz" | head -n1)

if [[ -n "$ARCHIVE_FILE" && -f "$ARCHIVE_FILE" ]]; then
  log_pass "Архив успешно создан в папке backup"
else
  log_fail "Архив не был создан"
fi


echo "[Тест 5] Проверка архивации ровно M самых старых файлов..."

rm -rf "\$TEST_LOG_DIR"/*
rm -rf "\$TEST_BACKUP_DIR"/*


touch -d "5 days ago" "\${TEST_LOG_DIR}/old_file.log"
touch -d "1 day ago" "\${TEST_LOG_DIR}/mid_file.log"
touch -d "10 seconds ago" "\${TEST_LOG_DIR}/new_file.log"


"$SCRIPT" "$TEST_LOG_DIR" 1 1 "\$TEST_BACKUP_DIR" > /dev/null 2>&1

ARCHIVE_FILE=$(find "$TEST_BACKUP_DIR" -name "log_backup_*.tar.gz" | head -n1)
if [[ -z "\$ARCHIVE_FILE" ]]; then
  log_fail "Архив не создан при наличии файлов"
else
  log_pass "Архив создан"
fi

ARCHIVED_FILES=$(tar -tf "$ARCHIVE_FILE")

if echo "$ARCHIVED_FILES" | grep -q "old_file.log" && ! echo "$ARCHIVED_FILES" | grep -q "new_file.log"; then
  log_pass "В архив попал самый старый файл, новые не затронуты"
else
  log_fail "Некорректная фильтрация файлов в архиве"
  echo "Содержимое архива: \$ARCHIVED_FILES"
fi

echo "[Тест 6] Проверка отсутствия архивации при нормальном уровне заполнения..."

rm -rf "\$TEST_LOG_DIR"/*
for i in {1..5}; do
  touch "${TEST_LOG_DIR}/tiny_${i}.log"
done


"$SCRIPT" "$TEST_LOG_DIR" 99 3 "\$TEST_BACKUP_DIR" > /dev/null 2>&1

NEW_ARCHIVES=$(find "$TEST_BACKUP_DIR" -name "log_backup_*.tar.gz" | wc -l)
if [[ "\$NEW_ARCHIVES" -eq 0 ]]; then
  log_pass "Архивация не произведена, так как порог не превышен"
else
  log_fail "Архив создан ошибочно, хотя порог не превышен"
fi


echo "[Тест 7] Проверка работы, если файлов меньше, чем запрошено (M)..."
rm -rf "\$TEST_LOG_DIR"/*
rm -rf "\$TEST_BACKUP_DIR"/*
touch "\${TEST_LOG_DIR}/only_one.log"

"$SCRIPT" "$TEST_LOG_DIR" 1 10 "\$TEST_BACKUP_DIR" > /dev/null 2>&1

ARCHIVE_FILE=$(find "$TEST_BACKUP_DIR" -name "log_backup_*.tar.gz" | head -n1)
if [[ -n "\$ARCHIVE_FILE" ]]; then
  log_pass "Архив создан даже при M > количества файлов"
else
  log_fail "Архив не создан, когда M больше количества файлов"
fi

echo "=== Все тесты завершены ==="
cleanup