#!/bin/bash

# Останавливаем скрипт при любой ошибке
set -e

# Проверяем, переданы ли аргументы
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "❌ Ошибка: Не указаны IP или ПОРТ целевого сервера."
  echo "Использование: curl -sSL ... | bash -s -- <IP> <PORT>"
  exit 1
fi

CASCADE_IP=$1
CASCADE_PORT=$2

echo "🚀 Начинаем настройку реле на PC1..."

# 1. Обновление и установка HAProxy
sudo apt update && sudo apt upgrade -y
sudo apt install -y haproxy

# 2. Создание резервной копии старого конфига
sudo mv /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak

# 3. Запись нового конфига через 'cat'
sudo bash -c "cat <<EOF > /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon

defaults
    log global
    mode tcp
    timeout connect 10s
    timeout client  2m
    timeout server  2m

frontend reality_in
    bind *:443
    default_backend cascade_out

backend cascade_out
    server cascade $CASCADE_IP:$CASCADE_PORT check
EOF"

# 4. Запуск и включение в автозагрузку
sudo systemctl enable haproxy
sudo systemctl restart haproxy

# 5. Проверка статуса
echo "📊 Статус HAProxy:"
sudo systemctl status haproxy --no-pager

# 6. Проверка связи с PC2
echo "🔍 Проверка связи с $CASCADE_IP:$CASCADE_PORT..."
if nc -vz -w 5 "$CASCADE_IP" "$CASCADE_PORT"; then
    echo "✅ Связь установлена! Реле работает на порту 443."
else
    echo "⚠️ Внимание: Не удалось достучаться до $CASCADE_IP:$CASCADE_PORT. Проверьте Firewall на PC2."
fi
