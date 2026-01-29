# Postfix + Dovecot для доменных пользователей ALD Pro / FreeIPA (Astra Linux SE 1.7.5.16)

Цель: развернуть **внутреннюю почту только внутри домена** `aldpro.lab` (без доступа извне) для доменных пользователей, с клиентами **Thunderbird**.

Рекомендованная схема (простая и рабочая):
- **Postfix**: SMTP-сервер (приём/отправка внутри сети), Submission **587** для клиентов.
- **Dovecot**: IMAP **993** (чтение почты), SASL-аутентификация для Postfix, доставка писем через **LMTP** в `Maildir`.
- **SSSD/FreeIPA (ALD)**: чтобы доменные пользователи были видны системе (`getent passwd user`), а Dovecot мог их аутентифицировать через **PAM/SSSD**.

> Примечание: ниже описан “быстрый, корректный” вариант для лаборатории. Для продакшена обычно добавляют антиспам/антивирус, квоты, резервное копирование, DKIM и т.д.

---

## 0) Что потребуется заранее

### 0.1 Имена и зона
Выберите FQDN почтового сервера (пример):
- **почтовик**: `mail.aldpro.lab`
- **домен почты**: `aldpro.lab`

Проверьте на сервере:

```bash
hostname -f
date
timedatectl status || true
```

Требования:
- `hostname -f` должен быть **mail.aldpro.lab** (или ваш выбранный FQDN)
- время синхронизировано (Kerberos/SSSD чувствительны к времени)

### 0.2 Порты (только внутренняя сеть)
Откройте доступ **только из локальной сети** к:
- **25/tcp** — SMTP (внутренняя доставка между серверами/хостами; в тестах может быть нужен)
- **587/tcp** — Submission (SMTP AUTH для пользователей из Thunderbird)
- **993/tcp** — IMAPS

> Не открывайте эти порты “наружу” и не пробрасывайте NAT — по условию доступ извне не нужен.

---

## 1) DNS в ALD/FreeIPA (внутренняя зона `aldpro.lab`)

Сделайте в DNS зоны `aldpro.lab`:
- **A**: `mail.aldpro.lab` → IP почтового сервера
- **MX**: для `aldpro.lab` указывает на `mail.aldpro.lab` (приоритет 10)

Проверка с любой машины в домене:

```bash
dig +short mail.aldpro.lab A
dig +short aldpro.lab MX
```

---

## 2) Почтовый сервер должен быть членом домена (SSSD)

### 2.1 Проверка: видим ли доменного пользователя как системного

```bash
getent passwd <domain_user>
id <domain_user>
```

Если команды возвращают пользователя — отлично, переходите к шагу 3.

Если **не возвращают**, значит сервер не введён в домен или не настроен NSS/SSSD. Для ALD/FreeIPA способы ввода в домен зависят от вашей роли (контроллер домена/член домена). В тестовом сценарии удобнее:
- либо поднимать почту **на контроллере** (тогда пользователи уже “есть”),
- либо корректно ввести отдельный сервер в домен через инструменты ALD/FreeIPA.

> Важно: без работающего `getent passwd <user>` корректной “доменной” аутентификации в Dovecot/Postfix не будет.

### 2.2 Автосоздание home (очень желательно для Maildir)
Проверьте, что при первом входе создаётся домашний каталог (обычно через `oddjob-mkhomedir` или PAM mkhomedir).

Проверка (примерно):

```bash
ls -ld /home/<domain_user> || true
```

Если home не создаётся автоматически, настраивайте mkhomedir по вашей доменной схеме (ALD/SSSD/PAM).

---

## 3) Установка пакетов (Postfix + Dovecot)

```bash
sudo apt-get update
sudo apt-get install -y postfix dovecot-core dovecot-imapd dovecot-lmtpd
```

Если установщик Postfix спросит:
- тип: **Internet Site**
- имя: `mail.aldpro.lab`

---

## 4) TLS (внутренний, без доступа извне)

Так как внешнего доступа нет, самый быстрый вариант — **самоподписанный сертификат** на `mail.aldpro.lab`.
Минус: на клиентах Thunderbird надо будет один раз “доверить” сертификат.

Создайте ключ и сертификат:

```bash
sudo install -d -m 0755 /etc/ssl/localcerts
sudo openssl req -new -x509 -days 3650 -nodes \
  -newkey rsa:2048 \
  -keyout /etc/ssl/localcerts/mail.aldpro.lab.key \
  -out /etc/ssl/localcerts/mail.aldpro.lab.crt \
  -subj "/C=RU/ST=LAB/L=LAB/O=ALDPRO/CN=mail.aldpro.lab"
sudo chmod 600 /etc/ssl/localcerts/mail.aldpro.lab.key
```

---

## 5) Настройка Dovecot (IMAPS + SASL + LMTP)

### 5.1 Maildir в домашнем каталоге
Откройте `/etc/dovecot/conf.d/10-mail.conf` и выставьте:

```conf
mail_location = maildir:~/Maildir
```

### 5.2 Аутентификация доменных пользователей через PAM/SSSD
Откройте `/etc/dovecot/conf.d/10-auth.conf` и проверьте:

```conf
disable_plaintext_auth = yes
auth_mechanisms = plain login
!include auth-system.conf.ext
```

### 5.3 TLS для Dovecot
Откройте `/etc/dovecot/conf.d/10-ssl.conf`:

```conf
ssl = required
ssl_cert = </etc/ssl/localcerts/mail.aldpro.lab.crt
ssl_key = </etc/ssl/localcerts/mail.aldpro.lab.key
```

### 5.4 Включить LMTP и сокеты для Postfix

1) Включите протоколы IMAP + LMTP (файл может быть `/etc/dovecot/dovecot.conf` или `conf.d/10-protocols.conf`):

```conf
protocols = imap lmtp
```

2) Откройте `/etc/dovecot/conf.d/10-master.conf` и добавьте/проверьте:

**SASL-сокет для Postfix:**

```conf
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
```

**LMTP-сокет для доставки:**

```conf
service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0600
    user = postfix
    group = postfix
  }
}
```

Перезапустите Dovecot:

```bash
sudo systemctl enable --now dovecot
sudo systemctl restart dovecot
```

Быстрый тест доменной аутентификации (замените пользователя/пароль):

```bash
sudo doveadm auth test <domain_user> '<PASSWORD>'
```

---

## 6) Настройка Postfix (внутренняя почта + Submission 587)

### 6.1 Базовая конфигурация `/etc/postfix/main.cf`
Откройте `/etc/postfix/main.cf` и приведите к следующей логике (подставьте ваши значения):

```conf
myhostname = mail.aldpro.lab
mydomain = aldpro.lab
myorigin = $mydomain

inet_interfaces = all
inet_protocols = all

# Доставляем "локальные" доменные адреса
mydestination = $myhostname, localhost.$mydomain, localhost, $mydomain

# Maildir в home (папка создастся при первом входе/первой доставке)
home_mailbox = Maildir/

# Доставка в Dovecot по LMTP (unix сокет мы создали в Dovecot)
mailbox_transport = lmtp:unix:private/dovecot-lmtp

# Включаем SMTP AUTH через Dovecot (SASL socket)
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes

# TLS для Postfix (внутренний самоподписанный)
smtpd_tls_cert_file=/etc/ssl/localcerts/mail.aldpro.lab.crt
smtpd_tls_key_file=/etc/ssl/localcerts/mail.aldpro.lab.key
smtpd_tls_security_level = may
smtpd_tls_auth_only = yes

# Запрещаем открытый relay: отправлять можно только "своим" и авторизованным
smtpd_recipient_restrictions =
  permit_sasl_authenticated,
  permit_mynetworks,
  reject_non_fqdn_recipient,
  reject_unknown_recipient_domain,
  check_recipient_access regexp:/etc/postfix/recipient_access,
  reject_unauth_destination

# Ограничьте "доверенные" сети (пример! замените на вашу подсеть/подсети)
mynetworks = 127.0.0.0/8 [::1]/128 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12
```

> Важно: `mynetworks` — это список сетей, которым вы доверяете *без* SMTP AUTH (например, если у вас есть внутренние устройства/скрипты).
> Если не уверены — оставьте только localhost и заставьте всех отправлять через 587 с паролем.

### 6.1.1 Жёстко ограничить получателей только доменом `aldpro.lab` (по условию “только внутри домена”)
Создайте файл `/etc/postfix/recipient_access`:

```conf
/^[^@]+$/            OK
/@aldpro\.lab$/      OK
/.*/                 REJECT only local mail for aldpro.lab is allowed
```

Примените:

```bash
sudo postfix reload
```

Пояснение:
- 1-я строка разрешает локальные адреса без `@` (например, `mail -s test user`)
- 2-я строка разрешает `user@aldpro.lab`
- 3-я блокирует любые внешние домены (например, `user@gmail.com`)

### 6.2 Включить Submission (587) в `/etc/postfix/master.cf`
Откройте `/etc/postfix/master.cf` и включите сервис `submission` (если есть — раскомментируйте и добавьте параметры):

```conf
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  # Важно: НЕ ослабляйте recipient_restrictions на submission, иначе аутентифицированные
  # пользователи смогут отправлять на внешние домены, обходя правила из main.cf.
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,permit_mynetworks,reject_non_fqdn_recipient,reject_unknown_recipient_domain,check_recipient_access regexp:/etc/postfix/recipient_access,reject_unauth_destination
  -o milter_macro_daemon_name=ORIGINATING
```

Перезапуск Postfix:

```bash
sudo systemctl enable --now postfix
sudo systemctl restart postfix
```

---

## 7) Минимальные ограничения “только внутри сети” (рекомендовано)

Смысл: даже если Postfix/Dovecot слушают `0.0.0.0`, доступ ограничиваем firewall’ом до внутренней сети.
Точный инструмент зависит от вашей политики Astra (nftables/iptables). Универсальный быстрый вариант через iptables (если у вас iptables-nft — тоже работает):

### 7.1 Пример iptables (разрешить только из подсети 192.168.50.0/24)
Замените подсеть на вашу!

```bash
LAN_NET="192.168.50.0/24"

sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A INPUT -i lo -j ACCEPT

sudo iptables -A INPUT -p tcp -s "$LAN_NET" --dport 25  -j ACCEPT
sudo iptables -A INPUT -p tcp -s "$LAN_NET" --dport 587 -j ACCEPT
sudo iptables -A INPUT -p tcp -s "$LAN_NET" --dport 993 -j ACCEPT

# (опционально) запретить доступ к этим портам со всех остальных
sudo iptables -A INPUT -p tcp --dport 25  -j DROP
sudo iptables -A INPUT -p tcp --dport 587 -j DROP
sudo iptables -A INPUT -p tcp --dport 993 -j DROP
```

> Как сохранять правила “навсегда” на Astra зависит от вашего стека (iptables-persistent/nftables/политики безопасности). Если скажете, чем вы пользуетесь (nft/iptables + persistent), добавлю точные команды сохранения.

---

## 8) Проверка сервера

### 8.1 Порты слушаются

```bash
sudo ss -lntp | egrep ':25|:587|:993'
```

### 8.2 Логи

```bash
sudo tail -n 200 /var/log/mail.log 2>/dev/null || true
sudo journalctl -u postfix -u dovecot --no-pager -n 200
```

### 8.3 Тест доставки “локально”
Отправьте письмо на доменного пользователя:

```bash
echo "Test internal mail" | mail -s "hello" <domain_user>@aldpro.lab
```

Если утилита `mail` отсутствует:

```bash
sudo apt-get install -y bsd-mailx
```

---

## 9) Настройка Thunderbird (Windows)

Создайте учётную запись:
- **Email**: `<domain_user>@aldpro.lab`
- **Входящая почта (IMAP)**:
  - сервер: `mail.aldpro.lab`
  - порт: **993**
  - SSL/TLS: **SSL/TLS**
  - аутентификация: **Обычный пароль**
  - имя пользователя: обычно `<domain_user>`
- **Исходящая почта (SMTP)**:
  - сервер: `mail.aldpro.lab`
  - порт: **587**
  - защита соединения: **STARTTLS**
  - аутентификация: **Обычный пароль**
  - имя пользователя: `<domain_user>`

Так как сертификат самоподписанный:
- при первом подключении Thunderbird попросит принять исключение/доверие — подтвердите (или импортируйте ваш внутренний CA в “Доверенные центры” Windows/Thunderbird).

---

## 10) Типовые проблемы (быстрое исправление)

- **`doveadm auth test` не проходит**:
  - проверьте `getent passwd <domain_user>` (SSSD/доменные учётки)
  - проверьте время на сервере (Kerberos)
  - смотрите `journalctl -u dovecot`

- **Thunderbird не отправляет (587)**:
  - проверьте, что `submission` включён в `master.cf`
  - проверьте, что используется **STARTTLS** и **порт 587**
  - смотрите `/var/log/mail.log` или `journalctl -u postfix`

- **Письмо не доставляется в Maildir**:
  - проверьте LMTP сокет `private/dovecot-lmtp` в Dovecot и `mailbox_transport` в Postfix
  - проверьте права на `/var/spool/postfix/private/…` (в примере выставлены правильные)
  - проверьте, что у пользователя есть home и права на `~/Maildir`

---

## 11) Быстрый чек-лист “готово/не готово”

1) DNS:
   - `MX aldpro.lab -> mail.aldpro.lab`
   - `A mail.aldpro.lab -> <IP>`
2) `getent passwd <user>` возвращает доменного пользователя
3) `ss -lntp` показывает порты: 25, 587, 993
4) `sudo doveadm auth test <user> '<pass>'` — OK
5) В Thunderbird:
   - IMAP 993 SSL/TLS
   - SMTP 587 STARTTLS + пароль


