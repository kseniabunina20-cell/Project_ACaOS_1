#!/bin/bash

if [ $# -ne 4 ]; then
    echo "Использование: $0 <log_dir> <threshold> <count> <backup_dir>"
    exit 1
fi

if [ ! -d "$1" ]; then
    echo "Папка $1 не найдена"
    exit 1
fi

if [ ! -d "$4" ]; then
    mkdir -p "$4"
fi

USAGE=$(df -P "$1" | tail -1 | awk '{print $5}' | cut -d'%' -f1)

echo "Занято: $USAGE%"

if [ "$USAGE" -gt "$2" ]; then
    echo "Превышен порог $2%"

    FILES=$(find "$1" -maxdepth 1 -type f -printf '%T@ %p\n' | sort -n | head -n "$3" | awk '{print $2}')

    if [ -z "$FILES" ]; then
        echo "Нет файлов для архивации"
        exit 0
    fi

    ARCHIVE="$4/log_backup_$(date +%Y%m%d_%H%M%S).tar.gz"

    echo "$FILES" | tar -czf "$ARCHIVE" -T -

    if [ $? -eq 0 ]; then
        echo "Архив создан: $ARCHIVE"
    else
        echo "Ошибка создания архива"
        exit 1
    fi
else
    echo "Места достаточно, архивация не нужна"
fi