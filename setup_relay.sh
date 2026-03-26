#!/bin/bash

# Останавливаем скрипт при любой ошибке
set -e

# Проверяем, передан ли IP
if [ -z "$1" ]; then
  echo "❌ Ошибка: Не указан IP целевого сервера (PC2)."
  echo "Использование: bash setup_relay.sh <IP_PC2>"
  exit 1
fi

CASCADE_IP=$1

# --- НАСТРОЙКА ДИАПАЗОНА ПОРТОВ ---
# Здесь укажи порты, которые хочешь пробросить
#PORTS=(443 4443 4444 4445 4446 4447 4448)
# Или можно задать диапазоном: PORTS=$(seq 4440 4450)
PORTS=$(seq 4440 5100)
# ----------------------------------

echo "🚀 Настройка реле на PC1 для IP: $CASCADE_IP"
echo "🔢 Будут проброшены порты: ${PORTS[*]}"

# 1. Установка HAProxy
sudo apt update && sudo apt install -y haproxy netcat-openbsd

# 2. Бекап старого конфига
[ -f /etc/haproxy/haproxy.cfg ] && sudo mv /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak

# 3. Формируем базовую часть конфига
cat <<EOF | sudo tee /etc/haproxy/haproxy.cfg > /dev/null
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon

defaults
    log global
    mode tcp
    timeout connect 10s
    timeout client  5m
    timeout server  5m
EOF

# 4. Циклом добавляем каждый порт в конфиг
for PORT in ${PORTS[@]}; do
    cat <<EOF | sudo tee -a /etc/haproxy/haproxy.cfg > /dev/null

frontend in_$PORT
    bind *:$PORT
    default_backend out_$PORT

backend out_$PORT
    server cascade_$PORT $CASCADE_IP:$PORT check
EOF
done

# 5. Перезапуск
sudo systemctl enable haproxy
sudo systemctl restart haproxy

echo "✅ HAProxy настроен!"

# 6. Проверка связи по каждому порту
echo "🔍 Проверка доступности портов на $CASCADE_IP:"
for PORT in ${PORTS[@]}; do
    if nc -vz -w 3 "$CASCADE_IP" "$PORT" 2>/dev/null; then
        echo "  [OK] Порт $PORT доступен"
    else
        echo "  [!!] Порт $PORT НЕ ОТВЕЧАЕТ (проверь Firewall на PC2)"
    fi
done

echo "🔗 Настройка завершена. Используй IP этого сервера и порты из списка выше."
