#!/bin/bash
# Использование: backup.sh <log_dir> <threshold_%> <count_M> <backup_dir> [pattern]
# pattern - маска фильтрации файлов (по умолчанию *.log)

if [ $# -lt 4 ] || [ $# -gt 5 ]; then
    echo "Использование: $0 <log_dir> <threshold> <count> <backup_dir> [pattern]"
    exit 1
fi

LOG_DIR="$1"
THRESHOLD="$2"
COUNT="$3"
BACKUP_DIR="$4"
PATTERN="${5:-*.log}"

if [ ! -d "$LOG_DIR" ]; then
    echo "Папка $LOG_DIR не найдена"
    exit 1
fi

if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]] || ! [[ "$COUNT" =~ ^[0-9]+$ ]]; then
    echo "Порог и количество файлов должны быть целыми числами"
    exit 1
fi

mkdir -p "$BACKUP_DIR" || { echo "Не удалось создать $BACKUP_DIR"; exit 1; }

USAGE=$(df -P "$LOG_DIR" | tail -1 | awk '{print $5}' | cut -d'%' -f1)
echo "Занято: $USAGE%"

if [ "$USAGE" -gt "$THRESHOLD" ]; then
    echo "Превышен порог $THRESHOLD%"

    LIST=$(mktemp)
    trap 'rm -f "$LIST"' EXIT

    # Фильтрация: только обычные файлы в корне папки, подходящие под маску,
    # непустые. Сортировка по времени изменения, берём M самых старых.
    find "$LOG_DIR" -maxdepth 1 -type f -name "$PATTERN" -size +0 -printf '%T@ %p\0' \
        | sort -z -n \
        | head -z -n "$COUNT" \
        | cut -z -d' ' -f2- > "$LIST"

    if [ ! -s "$LIST" ]; then
        echo "Нет файлов для архивации"
        exit 0
    fi

    ARCHIVE="$BACKUP_DIR/log_backup_$(date +%Y%m%d_%H%M%S).tar.gz"

    if tar --null -czf "$ARCHIVE" -T "$LIST" 2>/dev/null; then
        echo "Архив создан: $ARCHIVE"
        echo "Файлов в архиве: $(tr -cd '\0' < "$LIST" | wc -c)"
    else
        echo "Ошибка создания архива"
        exit 1
    fi
else
    echo "Места достаточно, архивация не нужна"
fi
