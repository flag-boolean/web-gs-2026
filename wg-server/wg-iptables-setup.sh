#!/usr/bin/env bash
set -euo pipefail

# wg-iptables-setup.sh
# Генерация и применение правил iptables для изоляции команд WireGuard
# Настраивается через переменные окружения. По умолчанию DRY_RUN=1 (только вывод)

# Пример использования:
# sudo NUM_TEAMS=5 SERVER_PUBLIC_IP=1.2.3.4 OUT_IF=eth1 OUT_IFS=eth1,eth2,eth3,eth4,eth5 DRY_RUN=0 ./wg-iptables-setup.sh

NUM_TEAMS=${NUM_TEAMS:-5}
ADMIN_PORT=${ADMIN_PORT:-51820}
WG_PORT_START=${WG_PORT_START:-51821}
SERVER_PUBLIC_IP=${SERVER_PUBLIC_IP:-}
OUT_IF=${OUT_IF:-eth1}
OUT_IFS=${OUT_IFS:-}   # необходимый список выходных интерфейсов для каждой команды через запятую, например "eth1,eth2,eth3,eth4,eth5"
VPN_PREFIX=${VPN_PREFIX:-10.201}         # база для VPN сетей команд: 10.201.1.0/24 ...
ADMIN_VPN=${ADMIN_VPN:-10.200.0.1/24}
TEAM_THIRD1=${TEAM_THIRD1:-30}            # третий октет для веб-хостов (например, 172.21.30.254)
TEAM_THIRD2=${TEAM_THIRD2:-31}            # опциональная вторая подсеть (например, 172.21.31.0/24)
PUBLIC_172_PREFIX=${PUBLIC_172_PREFIX:-172.2} # префикс: '172.2' -> команды 172.21,172.22,...
DRY_RUN=${DRY_RUN:-1}                     # 1 = только вывод, 0 = применить
ENABLE_ADMIN=${ENABLE_ADMIN:-0}           # 1 = добавить правила для admin интерфейса wg0

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo -e "${YELLOW}+ $*${NC}"
  else
    echo -e "${GREEN}RUN: $*${NC}"
    sudo sh -c "$*"
  fi
}

log_info "=== Настройка iptables для WireGuard ==="
log_info "Конфигурация: NUM_TEAMS=$NUM_TEAMS, WG_PORT_START=$WG_PORT_START, OUT_IF=$OUT_IF"
log_info "OUT_IFS=${OUT_IFS:-<не указано>}, DRY_RUN=$DRY_RUN, ENABLE_ADMIN=$ENABLE_ADMIN"

# Проверка прав root при применении правил
if [ "${DRY_RUN}" -eq 0 ] && [ "$EUID" -ne 0 ]; then
  log_error "Для применения правил нужны права root. Запустите с sudo:"
  log_error "  sudo DRY_RUN=0 ./wg-iptables-setup.sh"
  exit 1
fi

if [ "${DRY_RUN}" -eq 1 ]; then
  log_warn "DRY_RUN=1 — показываю действия. Для применения запустите:"
  log_warn "  sudo DRY_RUN=0 ./wg-iptables-setup.sh"
fi

# 1) Basic INPUT rules
log_info "Настройка базовых правил INPUT..."
run "iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT"
run "iptables -A INPUT -i lo -j ACCEPT"

# 2) Accept WireGuard handshake ports (admin + teams)
log_info "Разрешение UDP портов для WireGuard handshake..."
WG_PORTS="$ADMIN_PORT"
for i in $(seq 1 "$NUM_TEAMS"); do
  p=$((WG_PORT_START + i - 1))
  WG_PORTS="$WG_PORTS,$p"
done
run "iptables -A INPUT -p udp -m multiport --dports ${WG_PORTS} -j ACCEPT"

# 3) Admin interface (wg0) - опционально
if [ "${ENABLE_ADMIN}" -eq 1 ]; then
  log_info "Добавление правил для admin интерфейса wg0..."
  # Для admin можно разрешить более широкий доступ, здесь пример - разрешаем всё
  # Можно настроить более строгие правила при необходимости
  run "iptables -A INPUT -i wg0 -j ACCEPT"
fi

# 4) Allow team-specific HTTP access to .${TEAM_THIRD1}.254 only from its wg interface
log_info "Настройка доступа к веб-стендам для команд..."
for i in $(seq 1 "$NUM_TEAMS"); do
  wg_if=wg${i}
  pub_prefix="${PUBLIC_172_PREFIX}${i}"
  web_addr="${pub_prefix}.${TEAM_THIRD1}.254"
  log_info "  Команда $i: ${wg_if} -> ${web_addr}:80"
  run "iptables -A INPUT -i ${wg_if} -d ${web_addr} -p tcp --dport 80 -j ACCEPT"
done

# 5) Drop other INPUT traffic coming from team wg interfaces
log_info "Блокировка остального трафика с интерфейсов команд..."
for i in $(seq 1 "$NUM_TEAMS"); do
  wg_if=wg${i}
  run "iptables -A INPUT -i ${wg_if} -j DROP"
done

# 6) FORWARD rules: allow wgX -> its two /24 subnets (.${TEAM_THIRD1}.0/24 and .${TEAM_THIRD2}.0/24)
log_info "Настройка правил FORWARD для доступа команд к своим подсетям..."
run "iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT"

# Admin interface FORWARD (если включен)
if [ "${ENABLE_ADMIN}" -eq 1 ]; then
  log_info "  Admin (wg0): разрешаем весь трафик"
  run "iptables -A FORWARD -i wg0 -j ACCEPT"
fi

# Team interfaces FORWARD
for i in $(seq 1 "$NUM_TEAMS"); do
  wg_if=wg${i}
  pub_prefix="${PUBLIC_172_PREFIX}${i}"
  net1="${pub_prefix}.${TEAM_THIRD1}.0/24"
  net2="${pub_prefix}.${TEAM_THIRD2}.0/24"
  log_info "  Команда $i: ${wg_if} -> ${net1}, ${net2}"
  run "iptables -A FORWARD -i ${wg_if} -d ${net1} -p tcp -j ACCEPT"
  run "iptables -A FORWARD -i ${wg_if} -d ${net2} -p tcp -j ACCEPT"
  run "iptables -A FORWARD -i ${wg_if} -j DROP"
done

# 7) NAT (MASQUERADE) for VPN -> target lab networks if target VMs lack route back
# Support per-team output interfaces via OUT_IFS (CSV). If OUT_IFS is empty, fallback to OUT_IF.
log_info "Настройка NAT (MASQUERADE) для команд..."

# Парсинг OUT_IFS в массив
OUT_IF_ARR=()
if [ -n "${OUT_IFS:-}" ]; then
  IFS=',' read -r -a OUT_IF_ARR <<< "${OUT_IFS}"
fi

# Admin interface NAT (если включен)
if [ "${ENABLE_ADMIN}" -eq 1 ] && [ -n "${OUT_IF:-}" ]; then
  log_info "  Admin (wg0): MASQUERADE через ${OUT_IF}"
  # Извлекаем сеть из ADMIN_VPN (например, 10.200.0.1/24 -> 10.200.0.0/24)
  admin_net=$(echo "${ADMIN_VPN}" | sed 's|\([0-9]\+\.[0-9]\+\.[0-9]\+\)\.[0-9]\+/\([0-9]\+\)|\1.0/\2|')
  run "iptables -t nat -A POSTROUTING -s ${admin_net} -o ${OUT_IF} -j MASQUERADE"
fi

# Team interfaces NAT
for i in $(seq 1 "$NUM_TEAMS"); do
  vpn_src="${VPN_PREFIX}.${i}.0/24"
  pub_prefix="${PUBLIC_172_PREFIX}${i}"
  net1="${pub_prefix}.${TEAM_THIRD1}.0/24"
  net2="${pub_prefix}.${TEAM_THIRD2}.0/24"

  # Выбор выходного интерфейса для команды
  out_if=""
  idx=$((i-1))
  if [ "${#OUT_IF_ARR[@]}" -gt "$idx" ] && [ -n "${OUT_IF_ARR[$idx]}" ]; then
    out_if="${OUT_IF_ARR[$idx]}"
  else
    out_if="${OUT_IF:-}"
  fi

  if [ -z "$out_if" ]; then
    log_warn "Нет OUT_IF для команды $i, пропускаю MASQUERADE для ${vpn_src} -> ${net1},${net2}"
    continue
  fi

  log_info "  Команда $i: ${vpn_src} -> ${net1}, ${net2} через ${out_if}"
  run "iptables -t nat -A POSTROUTING -s ${vpn_src} -o ${out_if} -d ${net1} -j MASQUERADE"
  run "iptables -t nat -A POSTROUTING -s ${vpn_src} -o ${out_if} -d ${net2} -j MASQUERADE"
done

log_info "=== Настройка завершена ==="

if [ "${DRY_RUN}" -eq 0 ]; then
  log_info "Правила применены."
  log_info "Проверка правил:"
  echo "  sudo iptables -L INPUT -n -v --line-numbers"
  echo "  sudo iptables -L FORWARD -n -v --line-numbers"
  echo "  sudo iptables -t nat -L POSTROUTING -n -v --line-numbers"
  echo ""
  log_warn "ВАЖНО: Сохраните правила для перезагрузки:"
  echo "  sudo netfilter-persistent save"
  echo "  sudo systemctl enable --now netfilter-persistent"
else
  log_warn "Скрипт работал в режиме DRY_RUN. Для применения правил запустите:"
  log_warn "  sudo DRY_RUN=0 ./wg-iptables-setup.sh"
fi

echo ""
log_info "=== Следующие шаги ==="
echo "1. Проверьте правила: sudo iptables -S"
echo "2. Сохраните правила: sudo netfilter-persistent save"
echo "3. Проверьте интерфейсы WireGuard: sudo wg show"
echo "4. Проверьте порты: sudo ss -lunp | grep 5182"
echo ""
