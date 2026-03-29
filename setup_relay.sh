#!/bin/bash

# Останавливаем скрипт при любой ошибке
set -e

# 1. Проверка аргументов
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "❌ Ошибка: Недостаточно аргументов."
    echo "Использование: curl ... | bash -s -- <IP_PC2> <PORT>"
    echo "Пример: curl ... | bash -s -- 91.92.46.120 4481"
    exit 1
fi

CASCADE_IP=$1
PORT=$2

echo "🚀 Настройка Single-Port Relay на РУ-сервере..."
echo "📍 Целевой сервер (PC2): $CASCADE_IP"
echo "🔢 Порт для проброса: $PORT"

# 2. Обновление и установка необходимых утилит
sudo apt update
sudo apt install -y haproxy netcat-openbsd

# 3. Резервная копия старого конфига
if [ -f /etc/haproxy/haproxy.cfg ]; then
    sudo mv /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak
fi

# 4. Создание лаконичной конфигурации HAProxy (TCP Mode)
sudo bash -c "cat <<EOF > /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon
    maxconn 4096
    stats socket /run/haproxy.sock mode 660 level admin

defaults
    log global
    mode tcp
    option tcplog
    timeout connect 10s
    timeout client  1h
    timeout server  1h

frontend in_$PORT
    bind *:$PORT
    default_backend out_$PORT

backend out_$PORT
    server cascade_$PORT $CASCADE_IP:$PORT check inter 2000 rise 2 fall 3
EOF"

# 5. Включение в автозагрузку и запуск
sudo systemctl enable haproxy
sudo systemctl restart haproxy

# 6. Проверка статуса
if systemctl is-active --quiet haproxy; then
    echo "✅ HAProxy успешно запущен на порту $PORT!"
else
    echo "❌ Ошибка при запуске HAProxy. Проверьте логи: journalctl -u haproxy"
    exit 1
fi

# 7. Проверка связи с PC2
echo "🔍 Проверка связи с $CASCADE_IP:$PORT..."
if nc -vz -w 5 "$CASCADE_IP" "$PORT" 2>/dev/null; then
    echo "  [OK] Порт $PORT на PC2 доступен. Туннель пробит!"
else
    echo "  [!!] Порт $PORT на PC2 НЕ отвечает. Проверьте 3x-ui и Firewall на стороне PC2."
fi

echo "🔗 Настройка завершена. РУ-сервер пересылает трафик на $CASCADE_IP:$PORT"
