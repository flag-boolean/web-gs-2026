#!/usr/bin/env bash
# setup-postfix-ald.sh
# Скрипт развёртывания Postfix + Dovecot для внутренней почты ALD Pro / FreeIPA
# По умолчанию DRY_RUN=1 — скрипт покажет действия. Запускать с DRY_RUN=0 для применения:
#  sudo \
#   FQDN=mail.aldpro.lab \
#   DOMAIN=aldpro.lab \
#   LAB_NET1=172.21.30.0/24 \
#   LAB_NET2=172.21.31.0/24 \
#   APPLY_FIREWALL=1 \
#   DRY_RUN=0 \
#   ./setup-postfix-ald.sh
# Запуск со всеми параметрами

set -euo pipefail

# ---------------------
# Настройки (отредактируйте под свою сеть)
# ---------------------
FQDN="${FQDN:-mail.aldpro.lab}"
DOMAIN="${DOMAIN:-aldpro.lab}"

# Подсети лаборатории (для разных лабораторий задавайте через переменные окружения)
# По умолчанию: 172.21.30.0/24 и 172.21.31.0/24
LAB_NET1="${LAB_NET1:-172.21.30.0/24}"
LAB_NET2="${LAB_NET2:-172.21.31.0/24}"

# Подсеть(и), которым разрешён доступ к SMTP/IMAP (используется для firewall)
# По умолчанию: подсети лаборатории (LAB_NET1 и LAB_NET2)
# Можно переопределить через переменную окружения (разделитель пробел):
#   export LAN_NETS="192.168.50.0/24 10.0.0.0/8"
#   sudo DRY_RUN=0 ./setup-postfix-ald.sh
if [ -z "${LAN_NETS:-}" ]; then
  LAN_NETS_DEFAULT=("${LAB_NET1}" "${LAB_NET2}")
else
  # Преобразуем строку в массив (bash-совместимо)
  IFS=' ' read -ra LAN_NETS_DEFAULT <<< "${LAN_NETS}"
fi
LAN_NETS=("${LAN_NETS_DEFAULT[@]}")

# Доверенные сети для Postfix (включает подсети лаборатории)
# Можно переопределить через переменную MYNETWORKS
if [ -z "${MYNETWORKS:-}" ]; then
  MYNETWORKS="127.0.0.0/8 [::1]/128 ${LAB_NET1} ${LAB_NET2} 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12"
fi
# Пакеты для установки
PACKAGES=(postfix dovecot-core dovecot-imapd dovecot-lmtpd bsd-mailx openssl)

# Поведение
DRY_RUN=${DRY_RUN:-1}   # 1 = показывать, 0 = применить
APPLY_FIREWALL=${APPLY_FIREWALL:-0} # 1 = применить iptables правила из примера
SKIP_HOSTNAME=${SKIP_HOSTNAME:-0} # 1 = пропустить установку hostname
SKIP_PACKAGES=${SKIP_PACKAGES:-0} # 1 = пропустить установку пакетов

# Файловые пути
SSLDIR="/etc/ssl/localcerts"
KEYFILE="$SSLDIR/${FQDN}.key"
CRTFILE="$SSLDIR/${FQDN}.crt"
DOVECOT_DROPIN="/etc/dovecot/conf.d/99-ald.conf"
RECIP_FILE="/etc/postfix/recipient_access"

# Цвета для вывода (опционально)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Утилиты
run() {
  if [ "${DRY_RUN}" -eq 1 ]; then
    echo -e "${YELLOW}+ $*${NC}"
  else
    echo -e "${GREEN}RUN: $*${NC}"
    "$@"
  fi
}

log_info() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

# ---------------------
# Pre-checks
# ---------------------
if [ "$EUID" -ne 0 ] && [ "${DRY_RUN}" -eq 0 ]; then
  log_error "This script needs root to apply changes. Re-run with sudo or as root."
  exit 1
fi

log_info "=== Postfix + Dovecot Setup для ALD Pro ==="
log_info "Target FQDN: ${FQDN}"
log_info "Domain: ${DOMAIN}"
log_info "Подсети лаборатории: ${LAB_NET1}, ${LAB_NET2}"
log_info "LAN Networks (для firewall): ${LAN_NETS[*]}"
log_info "Доверенные сети Postfix (mynetworks): ${MYNETWORKS}"
if [ "${DRY_RUN}" -eq 1 ]; then
  log_warn "DRY_RUN=1 — показываю действия. Для применения запустите:"
  log_warn "  sudo DRY_RUN=0 ./setup-postfix-ald.sh"
fi

# Проверка текущего hostname
CURRENT_HOSTNAME=$(hostname -f 2>/dev/null || hostname)
if [ "${CURRENT_HOSTNAME}" != "${FQDN}" ]; then
  log_warn "Текущий hostname: ${CURRENT_HOSTNAME}, требуется: ${FQDN}"
  if [ "${SKIP_HOSTNAME}" -eq 0 ]; then
    log_info "Будет установлен hostname: ${FQDN}"
  fi
else
  log_info "Hostname уже установлен: ${FQDN}"
fi

# Проверка времени
if command -v timedatectl >/dev/null 2>&1; then
  if timedatectl status | grep -q "synchronized: yes"; then
    log_info "Время синхронизировано"
  else
    log_warn "Время может быть не синхронизировано (важно для Kerberos/SSSD)"
  fi
fi

# ---------------------
# 1) Set hostname
# ---------------------
if [ "${SKIP_HOSTNAME}" -eq 0 ]; then
  log_info "Установка hostname..."
  if [ "${DRY_RUN}" -eq 1 ]; then
    run hostnamectl set-hostname "${FQDN}"
  else
    if [ "${CURRENT_HOSTNAME}" != "${FQDN}" ]; then
      run hostnamectl set-hostname "${FQDN}"
      log_info "Hostname установлен. Может потребоваться перезагрузка."
    fi
  fi
else
  log_info "Пропуск установки hostname (SKIP_HOSTNAME=1)"
fi

# ---------------------
# 2) Install packages
# ---------------------
if [ "${SKIP_PACKAGES}" -eq 0 ]; then
  log_info "Установка пакетов: ${PACKAGES[*]}"
  if [ "${DRY_RUN}" -eq 1 ]; then
    run apt-get update
    run DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGES[@]}"
  else
    run apt-get update
    # Настройка postfix в неинтерактивном режиме
    export DEBIAN_FRONTEND=noninteractive
    echo "postfix postfix/main_mailer_type string Internet Site" | debconf-set-selections
    echo "postfix postfix/mailname string ${FQDN}" | debconf-set-selections
    run apt-get install -y "${PACKAGES[@]}"
  fi
else
  log_info "Пропуск установки пакетов (SKIP_PACKAGES=1)"
fi

# ---------------------
# 2.5) Проверка пользователя и группы postfix
# ---------------------
log_info "Проверка пользователя и группы postfix..."
if [ "${DRY_RUN}" -eq 1 ]; then
  run "getent passwd postfix >/dev/null 2>&1 || useradd -r -s /bin/false -d /var/spool/postfix -c 'Postfix MTA' postfix"
  run "getent group postfix >/dev/null 2>&1 || groupadd -r postfix"
else
  # Проверка и создание группы postfix
  if ! getent group postfix >/dev/null 2>&1; then
    log_warn "Группа postfix не найдена, создаю..."
    run groupadd -r postfix || true
    log_info "Группа postfix создана"
  else
    log_info "Группа postfix существует"
  fi
  
  # Проверка и создание пользователя postfix
  if ! getent passwd postfix >/dev/null 2>&1; then
    log_warn "Пользователь postfix не найден, создаю..."
    run useradd -r -s /bin/false -d /var/spool/postfix -c 'Postfix MTA' -g postfix postfix || true
    log_info "Пользователь postfix создан"
  else
    log_info "Пользователь postfix существует"
    # Убеждаемся, что пользователь в правильной группе
    if ! id -nG postfix | grep -q postfix; then
      log_warn "Добавляю пользователя postfix в группу postfix..."
      run usermod -a -G postfix postfix || true
    fi
  fi
  
  # Проверка каталога для сокетов
  if [ ! -d "/var/spool/postfix/private" ]; then
    log_info "Создание каталога /var/spool/postfix/private..."
    run mkdir -p /var/spool/postfix/private
    run chown postfix:postfix /var/spool/postfix/private
    run chmod 750 /var/spool/postfix/private
  fi
fi

# ---------------------
# 3) Create self-signed cert
# ---------------------
log_info "Создание самоподписанного SSL сертификата..."
if [ "${DRY_RUN}" -eq 1 ]; then
  run install -d -m 0755 "${SSLDIR}"
  run openssl req -new -x509 -days 3650 -nodes \
    -newkey rsa:2048 \
    -keyout "${KEYFILE}" \
    -out "${CRTFILE}" \
    -subj "/C=RU/ST=LAB/L=LAB/O=ALDPRO/CN=${FQDN}"
  run chmod 600 "${KEYFILE}"
else
  if [ ! -f "${KEYFILE}" ] || [ ! -f "${CRTFILE}" ]; then
    run install -d -m 0755 "${SSLDIR}"
    run openssl req -new -x509 -days 3650 -nodes \
      -newkey rsa:2048 \
      -keyout "${KEYFILE}" \
      -out "${CRTFILE}" \
      -subj "/C=RU/ST=LAB/L=LAB/O=ALDPRO/CN=${FQDN}"
    run chmod 600 "${KEYFILE}"
    log_info "Сертификат создан: ${CRTFILE}"
    
    # Создаем копию сертификата для распространения на клиенты
    CERT_COPY="/root/${FQDN}.crt"
    if [ ! -f "${CERT_COPY}" ]; then
      run cp "${CRTFILE}" "${CERT_COPY}"
      run chmod 644 "${CERT_COPY}"
      log_info "Копия сертификата для клиентов создана: ${CERT_COPY}"
    fi
  else
    log_info "Сертификат уже существует, пропускаю создание"
    # Проверяем наличие копии для клиентов
    CERT_COPY="/root/${FQDN}.crt"
    if [ ! -f "${CERT_COPY}" ] && [ -f "${CRTFILE}" ]; then
      run cp "${CRTFILE}" "${CERT_COPY}"
      run chmod 644 "${CERT_COPY}"
      log_info "Копия сертификата для клиентов создана: ${CERT_COPY}"
    fi
  fi
fi

# ---------------------
# 4) Dovecot configuration (create a single conf drop-in)
# ---------------------
log_info "Настройка Dovecot..."
if [ "${DRY_RUN}" -eq 1 ]; then
  echo "--- DRY RUN: would write ${DOVECOT_DROPIN} ---"
  cat <<EOF
# Dovecot settings for ALD internal mail (managed by setup-postfix-ald.sh)
protocols = imap lmtp

mail_location = maildir:~/Maildir

disable_plaintext_auth = yes
auth_mechanisms = plain login
!include auth-system.conf.ext

ssl = required
ssl_cert = <${CRTFILE}
ssl_key = <${KEYFILE}

service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}

service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0600
    user = postfix
    group = postfix
  }
}
EOF
else
  cat > "${DOVECOT_DROPIN}" <<EOF
# Dovecot settings for ALD internal mail (managed by setup-postfix-ald.sh)
protocols = imap lmtp

mail_location = maildir:~/Maildir

disable_plaintext_auth = yes
auth_mechanisms = plain login
!include auth-system.conf.ext

ssl = required
ssl_cert = <${CRTFILE}
ssl_key = <${KEYFILE}

service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}

service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0600
    user = postfix
    group = postfix
  }
}
EOF
  log_info "Конфигурация Dovecot записана в ${DOVECOT_DROPIN}"
  run systemctl enable --now dovecot || true
  run systemctl restart dovecot || true
  log_info "Dovecot перезапущен"
fi

# ---------------------
# 5) Postfix configuration via postconf + files
# ---------------------
log_info "Настройка Postfix..."

if [ "${DRY_RUN}" -eq 1 ]; then
  echo "--- DRY RUN: would configure Postfix via postconf ---"
  echo "postconf -e \"myhostname = ${FQDN}\""
  echo "postconf -e \"mydomain = ${DOMAIN}\""
  echo "postconf -e \"myorigin = \$mydomain\""
  echo "postconf -e \"inet_interfaces = all\""
  echo "postconf -e \"inet_protocols = all\""
  echo "postconf -e \"mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain\""
  echo "postconf -e \"home_mailbox = Maildir/\""
  echo "postconf -e \"mailbox_transport = lmtp:unix:private/dovecot-lmtp\""
  echo "postconf -e \"smtpd_sasl_type = dovecot\""
  echo "postconf -e \"smtpd_sasl_path = private/auth\""
  echo "postconf -e \"smtpd_sasl_auth_enable = yes\""
  echo "postconf -e \"smtpd_tls_cert_file=${CRTFILE}\""
  echo "postconf -e \"smtpd_tls_key_file=${KEYFILE}\""
  echo "postconf -e \"smtpd_tls_security_level = may\""
  echo "postconf -e \"smtpd_tls_auth_only = yes\""
  echo "postconf -e \"mynetworks = ${MYNETWORKS}\""
  echo "postconf -e \"smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mynetworks, reject_non_fqdn_recipient, reject_unknown_recipient_domain, check_recipient_access regexp:${RECIP_FILE}, reject_unauth_destination\""
else
  if command -v postconf >/dev/null 2>&1; then
    run postconf -e "myhostname = ${FQDN}"
    run postconf -e "mydomain = ${DOMAIN}"
    run postconf -e "myorigin = \$mydomain"
    run postconf -e "inet_interfaces = all"
    run postconf -e "inet_protocols = all"
    run postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
    run postconf -e "home_mailbox = Maildir/"
    run postconf -e "mailbox_transport = lmtp:unix:private/dovecot-lmtp"
    run postconf -e "smtpd_sasl_type = dovecot"
    run postconf -e "smtpd_sasl_path = private/auth"
    run postconf -e "smtpd_sasl_auth_enable = yes"
    run postconf -e "smtpd_tls_cert_file=${CRTFILE}"
    run postconf -e "smtpd_tls_key_file=${KEYFILE}"
    run postconf -e "smtpd_tls_security_level = may"
    run postconf -e "smtpd_tls_auth_only = yes"
    run postconf -e "mynetworks = ${MYNETWORKS}"
    run postconf -e "smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mynetworks, reject_non_fqdn_recipient, reject_unknown_recipient_domain, check_recipient_access regexp:${RECIP_FILE}, reject_unauth_destination"
    log_info "Postfix настроен через postconf"
  else
    log_error "postconf не найден. Установите postfix."
    exit 1
  fi
fi

# recipient_access (regexp) - ограничение только доменом
log_info "Создание файла recipient_access..."
if [ "${DRY_RUN}" -eq 1 ]; then
  echo "--- DRY RUN: would write ${RECIP_FILE} ---"
  cat <<EOF
/^[^@]+\$/            OK
/@${DOMAIN//./\\.}\$/      OK
/.*/                 REJECT only local mail for ${DOMAIN} is allowed
EOF
else
  cat > "${RECIP_FILE}" <<EOF
/^[^@]+\$/            OK
/@${DOMAIN//./\\.}\$/      OK
/.*/                 REJECT only local mail for ${DOMAIN} is allowed
EOF
  run postmap "${RECIP_FILE}" || true
  log_info "Файл recipient_access создан"
fi

if [ "${DRY_RUN}" -eq 0 ]; then
  run postfix reload || true
fi

# Ensure submission service enabled in master.cf
log_info "Проверка submission сервиса в master.cf..."
if [ "${DRY_RUN}" -eq 1 ]; then
  if ! grep -q "^submission" /etc/postfix/master.cf 2>/dev/null; then
    echo "--- DRY RUN: would add submission service to /etc/postfix/master.cf ---"
    cat <<EOF
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,permit_mynetworks,reject_non_fqdn_recipient,reject_unknown_recipient_domain,check_recipient_access regexp:${RECIP_FILE},reject_unauth_destination
  -o milter_macro_daemon_name=ORIGINATING
EOF
  else
    log_info "submission сервис уже настроен в master.cf"
  fi
else
  if ! grep -q "^submission" /etc/postfix/master.cf 2>/dev/null; then
    log_info "Добавление submission сервиса в master.cf..."
    cat >> /etc/postfix/master.cf <<EOF
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,permit_mynetworks,reject_non_fqdn_recipient,reject_unknown_recipient_domain,check_recipient_access regexp:${RECIP_FILE},reject_unauth_destination
  -o milter_macro_daemon_name=ORIGINATING
EOF
    log_info "submission сервис добавлен"
  else
    log_info "submission сервис уже настроен в master.cf"
  fi
  run systemctl enable --now postfix || true
  run systemctl restart postfix || true
  log_info "Postfix перезапущен"
fi

# ---------------------
# 6) Firewall (optional)
# ---------------------
if [ "${APPLY_FIREWALL}" -eq 1 ]; then
  log_info "Применение правил iptables для LAN_NETS..."
  if command -v iptables >/dev/null 2>&1; then
    for net in "${LAN_NETS[@]}"; do
      log_info "Настройка правил для сети: ${net}"
      if [ "${DRY_RUN}" -eq 1 ]; then
        run iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        run iptables -A INPUT -i lo -j ACCEPT
        run iptables -A INPUT -p tcp -s "${net}" --dport 25 -j ACCEPT
        run iptables -A INPUT -p tcp -s "${net}" --dport 587 -j ACCEPT
        run iptables -A INPUT -p tcp -s "${net}" --dport 993 -j ACCEPT
        run iptables -A INPUT -p tcp --dport 25 -j DROP
        run iptables -A INPUT -p tcp --dport 587 -j DROP
        run iptables -A INPUT -p tcp --dport 993 -j DROP
      else
        # Проверяем, не добавлены ли уже правила
        if ! iptables -C INPUT -p tcp -s "${net}" --dport 25 -j ACCEPT 2>/dev/null; then
          run iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT || true
          run iptables -A INPUT -i lo -j ACCEPT || true
          run iptables -A INPUT -p tcp -s "${net}" --dport 25 -j ACCEPT
          run iptables -A INPUT -p tcp -s "${net}" --dport 587 -j ACCEPT
          run iptables -A INPUT -p tcp -s "${net}" --dport 993 -j ACCEPT
          run iptables -A INPUT -p tcp --dport 25 -j DROP
          run iptables -A INPUT -p tcp --dport 587 -j DROP
          run iptables -A INPUT -p tcp --dport 993 -j DROP
          log_warn "Правила iptables добавлены. Не забудьте сохранить их (iptables-save > /etc/iptables/rules.v4 или аналогично)"
        else
          log_info "Правила для ${net} уже существуют"
        fi
      fi
    done
  else
    log_error "iptables не найден. Пропускаю настройку firewall."
  fi
else
  log_info "Пропуск настройки firewall (APPLY_FIREWALL=0). Для применения используйте: APPLY_FIREWALL=1"
fi

# ---------------------
# 7) Final checks / instructions
# ---------------------
log_info "=== Установка завершена (DRY_RUN=${DRY_RUN}) ==="

if [ "${DRY_RUN}" -eq 0 ]; then
  log_info "Проверка статуса сервисов..."
  if systemctl is-active --quiet postfix; then
    log_info "✓ Postfix запущен"
  else
    log_error "✗ Postfix не запущен"
  fi
  
  if systemctl is-active --quiet dovecot; then
    log_info "✓ Dovecot запущен"
  else
    log_error "✗ Dovecot не запущен"
  fi
  
  log_info "Проверка портов..."
  if command -v ss >/dev/null 2>&1; then
    run ss -lntp | grep -E ':25|:587|:993' || log_warn "Порты 25, 587 или 993 не слушаются"
  fi
fi

echo ""
log_info "=== Следующие шаги ==="
echo "1. Проверьте порты: sudo ss -lntp | grep -E ':25|:587|:993'"
echo "2. Проверьте логи: sudo journalctl -u postfix -u dovecot --no-pager -n 200"
echo "3. Проверьте доменного пользователя: getent passwd <domain_user>"
echo "4. Тест аутентификации: sudo doveadm auth test <domain_user> '<PASSWORD>'"
echo "5. Тест отправки: echo 'Test' | mail -s 'Test' <domain_user>@${DOMAIN}"
echo ""
log_warn "ВАЖНО: Убедитесь, что доменные пользователи доступны через SSSD/FreeIPA"
log_warn "       (команда 'getent passwd <user>' должна возвращать пользователя)"
echo ""
log_info "Настройка Thunderbird:"
echo "  - IMAP: ${FQDN}:993 (SSL/TLS)"
echo "  - SMTP: ${FQDN}:587 (STARTTLS)"
echo "  - Email: <domain_user>@${DOMAIN}"
echo ""
log_warn "=== УСТАНОВКА SSL СЕРТИФИКАТА НА КЛИЕНТСКИХ МАШИНАХ ==="
echo ""
if [ "${DRY_RUN}" -eq 0 ] && [ -f "${CRTFILE}" ]; then
  CERT_COPY="/root/${FQDN}.crt"
  if [ -f "${CERT_COPY}" ]; then
    log_info "Сертификат для клиентов находится: ${CERT_COPY}"
    echo "Скопируйте этот файл на клиентские машины (где установлен Thunderbird)"
    echo ""
    echo "Способы копирования:"
    echo "  1. Через SCP: scp ${CERT_COPY} user@client-machine:/tmp/"
    echo "  2. Через общий каталог/флешку"
    echo ""
    echo "Установка на клиентской машине (Linux):"
    echo "  # Вариант 1: Добавить в системные доверенные сертификаты"
    echo "  sudo cp ${FQDN}.crt /usr/local/share/ca-certificates/${FQDN}.crt"
    echo "  sudo update-ca-certificates"
    echo ""
    echo "  # Вариант 2: Добавить в Thunderbird напрямую"
    echo "  # Thunderbird -> Настройки -> Конфиденциальность и безопасность -> Сертификаты"
    echo "  # -> Просмотр сертификатов -> Ваши сертификаты -> Импорт"
    echo ""
    echo "Установка на клиентской машине (Windows):"
    echo "  1. Скопируйте ${FQDN}.crt на Windows машину"
    echo "  2. Двойной клик по файлу -> Установить сертификат"
    echo "  3. Выберите 'Текущий пользователь' или 'Локальный компьютер'"
    echo "  4. Разместить сертификат: 'Поместить все сертификаты в следующее хранилище'"
    echo "  5. Нажмите 'Обзор' -> выберите 'Доверенные корневые центры сертификации'"
    echo "  6. Нажмите 'Далее' -> 'Готово'"
    echo ""
    echo "  ИЛИ в Thunderbird:"
    echo "  Thunderbird -> Настройки -> Конфиденциальность и безопасность -> Сертификаты"
    echo "  -> Просмотр сертификатов -> Ваши сертификаты -> Импорт"
    echo ""
    log_warn "ВАЖНО: Без установки сертификата Thunderbird будет показывать"
    log_warn "       предупреждение о недоверенном сертификате при каждом подключении"
  fi
else
  log_info "Сертификат для клиентов будет создан после применения скрипта"
  log_info "Расположение: /root/${FQDN}.crt"
fi
echo ""
