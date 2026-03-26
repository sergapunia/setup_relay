#!/bin/bash

# Останавливаем скрипт при любой ошибке
set -e

# Проверяем, переданы ли аргументы
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "❌ Ошибка: Не указаны IP или ПОРТ целевого сервера (PC2)."
  echo "Использование: curl -sSL https://raw.githubusercontent.com/sergapunia/setup_relay/main/setup_relay.sh | bash -s -- <IP_PC2> <PORT_PC2>"
  exit 1
fi

CASCADE_IP=$1
CASCADE_PORT=$2

echo "🚀 Начинаем настройку реле на PC1..."

# 1. Обновление списков пакетов и установка HAProxy и Netcat (для проверки связи)
sudo apt update
sudo apt install -y haproxy netcat-openbsd

# 2. Создание резервной копии старого конфига (если он есть)
if [ -f /etc/haproxy/haproxy.cfg ]; then
    sudo mv /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak
fi

# 3. Запись нового конфига через 'cat'
# Мы используем кавычки вокруг "EOF", чтобы переменные внутри (CASCADE_IP) подставились из bash
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

# 4. Включение в автозагрузку и запуск
sudo systemctl enable haproxy
sudo systemctl restart haproxy

# 5. Проверка статуса (кратко)
echo "📊 Статус HAProxy:"
sudo systemctl is-active haproxy

# 6. Проверка связи с PC2
echo "🔍 Проверка связи с $CASCADE_IP:$CASCADE_PORT..."
# Используем nc для проверки порта. -z — скан, -w 5 — таймаут 5 сек
if nc -vz -w 5 "$CASCADE_IP" "$CASCADE_PORT" 2>/dev/null; then
    echo "✅ Связь установлена! PC1 успешно видит порт PC2."
    echo "🔗 Теперь подключайся к PC1 ($HOSTNAME или IP) по порту 443."
else
    echo "⚠️ ВНИМАНИЕ: Не удалось достучаться до $CASCADE_IP:$CASCADE_PORT."
    echo "Проверь, открыт ли порт $CASCADE_PORT в Firewall (Security Groups) на PC2."
fi
