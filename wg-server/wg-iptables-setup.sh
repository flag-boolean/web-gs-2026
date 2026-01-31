#!/usr/bin/env bash
set -euo pipefail

# wg-iptables-setup.sh
# Generates and (optionally) applies iptables rules for WireGuard team isolation.
# Configurable via environment variables. Default is DRY_RUN=1 (print only).

# Usage example:
# NUM_TEAMS=5 SERVER_PUBLIC_IP=1.2.3.4 OUT_IF=eth1 DRY_RUN=0 ./wg-iptables-setup.sh
# Скрипт автоматизированной настройки правил IPTABLES


NUM_TEAMS=${NUM_TEAMS:-5}
ADMIN_PORT=${ADMIN_PORT:-51820}
WG_PORT_START=${WG_PORT_START:-51821}
SERVER_PUBLIC_IP=${SERVER_PUBLIC_IP:-}
OUT_IF=${OUT_IF:-eth1}
OUT_IFS=${OUT_IFS:-}   # optional comma-separated list of output interfaces per team, e.g. "eth1,eth2,eth3,eth4,eth5"
VPN_PREFIX=${VPN_PREFIX:-10.201}         # base for team VPN nets: 10.201.1.0/24 ...
ADMIN_VPN=${ADMIN_VPN:-10.200.0.1/24}
TEAM_THIRD1=${TEAM_THIRD1:-30}            # third octet for web hosts (e.g. 172.21.30.254)
TEAM_THIRD2=${TEAM_THIRD2:-31}            # optional second subnet (e.g. 172.21.31.0/24)
PUBLIC_172_PREFIX=${PUBLIC_172_PREFIX:-172.2} # prefix: '172.2' -> teams 172.21,172.22,...
DRY_RUN=${DRY_RUN:-1}                     # 1 = print only, 0 = apply

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "+ $*"
  else
    echo "RUN: $*"
    sudo sh -c "$*"
  fi
}

echo "Config: NUM_TEAMS=$NUM_TEAMS, WG_PORT_START=$WG_PORT_START, OUT_IF=$OUT_IF, OUT_IFS=${OUT_IFS:-<none>}, DRY_RUN=$DRY_RUN"

# 1) Basic INPUT rules
run "iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT"
run "iptables -A INPUT -i lo -j ACCEPT"

# 2) Accept WireGuard handshake ports (admin + teams)
WG_PORTS="$ADMIN_PORT"
for i in $(seq 1 "$NUM_TEAMS"); do
  p=$((WG_PORT_START + i - 1))
  WG_PORTS="$WG_PORTS,$p"
done
run "iptables -A INPUT -p udp -m multiport --dports ${WG_PORTS} -j ACCEPT"

# 3) Allow team-specific HTTP access to .${TEAM_THIRD1}.254 only from its wg interface
for i in $(seq 1 "$NUM_TEAMS"); do
  wg_if=wg${i}
  pub_prefix="${PUBLIC_172_PREFIX}${i}"
  web_addr="${pub_prefix}.${TEAM_THIRD1}.254"
  run "iptables -A INPUT -i ${wg_if} -d ${web_addr} -p tcp --dport 80 -j ACCEPT"
done

# 4) Drop other INPUT traffic coming from team wg interfaces
for i in $(seq 1 "$NUM_TEAMS"); do
  wg_if=wg${i}
  run "iptables -A INPUT -i ${wg_if} -j DROP"
done

# 5) FORWARD rules: allow wgX -> its two /24 subnets (.${TEAM_THIRD1}.0/24 and .${TEAM_THIRD2}.0/24)
run "iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT"
for i in $(seq 1 "$NUM_TEAMS"); do
  wg_if=wg${i}
  pub_prefix="${PUBLIC_172_PREFIX}${i}"
  net1="${pub_prefix}.${TEAM_THIRD1}.0/24"
  net2="${pub_prefix}.${TEAM_THIRD2}.0/24"
  run "iptables -A FORWARD -i ${wg_if} -d ${net1} -p tcp -j ACCEPT"
  run "iptables -A FORWARD -i ${wg_if} -d ${net2} -p tcp -j ACCEPT"
  run "iptables -A FORWARD -i ${wg_if} -j DROP"
done

# 6) NAT (MASQUERADE) for VPN -> target lab networks if target VMs lack route back
# Support per-team output interfaces via OUT_IFS (CSV). If OUT_IFS is empty, fallback to OUT_IF.
IFS=',' read -r -a OUT_IF_ARR <<< "${OUT_IFS}"
for i in $(seq 1 "$NUM_TEAMS"); do
  vpn_src="${VPN_PREFIX}.${i}.0/24"
  pub_prefix="${PUBLIC_172_PREFIX}${i}"
  net1="${pub_prefix}.${TEAM_THIRD1}.0/24"
  net2="${pub_prefix}.${TEAM_THIRD2}.0/24"

  # choose per-team out interface if provided, else fallback to OUT_IF
  out_if=""
  idx=$((i-1))
  if [ "${#OUT_IF_ARR[@]}" -gt "$idx" ] && [ -n "${OUT_IF_ARR[$idx]}" ]; then
    out_if="${OUT_IF_ARR[$idx]}"
  else
    out_if="$OUT_IF"
  fi

  if [ -z "$out_if" ]; then
    echo "No OUT_IF for team $i, skipping MASQUERADE for ${vpn_src} -> ${net1},${net2}"
    continue
  fi

  run "iptables -t nat -A POSTROUTING -s ${vpn_src} -o ${out_if} -d ${net1} -j MASQUERADE"
  run "iptables -t nat -A POSTROUTING -s ${vpn_src} -o ${out_if} -d ${net2} -j MASQUERADE"
done

echo "Done. To persist rules run: sudo netfilter-persistent save"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "Script was in DRY_RUN mode. Set DRY_RUN=0 to apply the rules.";
fi
