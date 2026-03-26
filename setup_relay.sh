#!/bin/bash

# Останавливаем скрипт при любой ошибке
set -e

# 1. Проверка аргументов
# Нам нужен как минимум один IP ($1) и один ПОРТ ($2)
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "❌ Ошибка: Недостаточно аргументов."
    echo "Использование: curl ... | bash -s -- <IP_PC2> <PORT1> <PORT2> ..."
    echo "Пример для диапазона: curl ... | bash -s -- 1.2.3.4 \$(seq 4440 4510)"
    exit 1
fi

CASCADE_IP=$1
shift # Убираем IP из списка, теперь в \$@ только порты
PORTS=("$@")

echo "🚀 Настройка Multi-Port Relay на PC1..."
echo "📍 Целевой сервер (PC2): $CASCADE_IP"
echo "🔢 Количество портов для проброса: ${#PORTS[@]}"

# 2. Обновление и установка необходимых утилит
sudo apt update
sudo apt install -y haproxy netcat-openbsd

# 3. Резервная копия старого конфига
if [ -f /etc/haproxy/haproxy.cfg ]; then
    sudo mv /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak
fi

# 4. Создание базовой части конфигурации HAProxy
sudo bash -c "cat <<EOF > /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon
    maxconn 4096

defaults
    log global
    mode tcp
    option tcplog
    timeout connect 10s
    timeout client  5m
    timeout server  5m
EOF"

# 5. Циклическое добавление каждого порта в конфиг
echo "📝 Генерируем конфигурацию для портов..."
for PORT in "${PORTS[@]}"; do
    sudo bash -c "cat <<EOF >> /etc/haproxy/haproxy.cfg

frontend in_$PORT
    bind *:$PORT
    default_backend out_$PORT

backend out_$PORT
    server cascade_$PORT $CASCADE_IP:$PORT check
EOF"
done

# 6. Включение в автозагрузку и запуск HAProxy
sudo systemctl enable haproxy
sudo systemctl restart haproxy

# 7. Проверка статуса
if systemctl is-active --quiet haproxy; then
    echo "✅ HAProxy успешно запущен!"
else
    echo "❌ Ошибка при запуске HAProxy. Проверьте логи: journalctl -u haproxy"
    exit 1
fi

# 8. Финальная проверка связи с PC2 (выборочно для первого и последнего порта)
FIRST_PORT=${PORTS[0]}
LAST_PORT=${PORTS[-1]}

echo "🔍 Выборочная проверка связи с $CASCADE_IP..."
for CHECK_PORT in $FIRST_PORT $LAST_PORT; do
    if nc -vz -w 3 "$CASCADE_IP" "$CHECK_PORT" 2>/dev/null; then
        echo "  [OK] Порт $CHECK_PORT на PC2 доступен."
    else
        echo "  [!!] Порт $CHECK_PORT на PC2 НЕ отвечает. Проверьте Firewall на стороне PC2!"
    fi
done

echo "🔗 Настройка завершена. Теперь все запросы на порты ${FIRST_PORT}-${LAST_PORT} этого сервера будут уходить на $CASCADE_IP."
