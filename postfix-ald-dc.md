# Postfix + Dovecot на контроллере домена ALD (`alddc01.aldpro.lab`) — внутренняя почта для доменных пользователей

Цель: развернуть **внутреннюю почту только внутри домена** `aldpro.lab` прямо на контроллере домена **`alddc01.aldpro.lab`** (Astra Linux SE 1.7.5.16), с клиентами **Thunderbird на Windows**.

Используем:
- **Postfix** — SMTP (25) и Submission (587) для доменных пользователей.
- **Dovecot** — IMAP (993) + LMTP для доставки в `Maildir`.
- Уже имеющийся стек **FreeIPA/ALD** на контроллере: пользователи, Kerberos, SSSD, DNS.

> Важно: эта инструкция — адаптация `postfix-ald.md` под ситуацию, когда почтовый сервер и контроллер домена — одна и та же машина `alddc01.aldpro.lab`.

---

## 0) Базовые условия и имена

### 0.1 Текущее имя контроллера

Проверьте:

```bash
hostname -f
```

Ожидаем:

- `hostname -f` возвращает **`alddc01.aldpro.lab`**.

### 0.2 Как будем называть почтовый сервер

Есть два варианта:

- **Вариант 1 (проще)**: использовать само имя контроллера как имя почтовика.
  - MX → `alddc01.aldpro.lab`
  - В `main.cf`: `myhostname = alddc01.aldpro.lab`
  - В Thunderbird: сервер `alddc01.aldpro.lab`.

- **Вариант 2 (красивее)**: завести alias `mail.aldpro.lab`, указывающий на тот же IP.
  - A: `mail.aldpro.lab -> IP alddc01`
  - MX → `mail.aldpro.lab`
  - В `main.cf`: `myhostname = mail.aldpro.lab`
  - В Thunderbird: сервер `mail.aldpro.lab`.

Дальше в примере используем **Вариант 2** (с `mail.aldpro.lab`), но можно оставить `alddc01.aldpro.lab` — тогда везде просто подставляйте его.

---

## 1) DNS в ALD/FreeIPA (зона `aldpro.lab`)

Внутренние DNS-записи:

- **A**: `mail.aldpro.lab` → IP контроллера (тот же, что у `alddc01.aldpro.lab`)
- **MX**: для `aldpro.lab` указывает на `mail.aldpro.lab` (приоритет 10)

Проверка с любой доменной машины:

```bash
dig +short mail.aldpro.lab A
dig +short aldpro.lab MX
```

---

## 2) Пользователи домена уже есть (SSSD настроен)

Контроллер домена уже “видит” доменных пользователей.
Проверка (для уверенности):

```bash
getent passwd <domain_user>
id <domain_user>
```

Если команды возвращают пользователя — всё хорошо, можно идти дальше.

> Домашние каталоги: проверьте, где у вас лежат home у доменных пользователей (локально / по NFS). Для Maildir **важно**, чтобы home был доступен и на контроллере было достаточно места на диске.

---

## 3) Установка пакетов (Postfix + Dovecot)

```bash
sudo apt-get update
sudo apt-get install -y postfix dovecot-core dovecot-imapd dovecot-lmtpd bsd-mailx
```

При установке Postfix:
- тип: **Internet Site**
- имя: `mail.aldpro.lab` (или `alddc01.aldpro.lab`, если решили не делать alias)

---

## 4) TLS (самоподписанный сертификат для внутренней сети)

Внешнего доступа нет, поэтому делаем самоподписанный сертификат на `mail.aldpro.lab`.

```bash
sudo install -d -m 0755 /etc/ssl/localcerts
sudo openssl req -new -x509 -days 3650 -nodes \
  -newkey rsa:2048 \
  -keyout /etc/ssl/localcerts/mail.aldpro.lab.key \
  -out /etc/ssl/localcerts/mail.aldpro.lab.crt \
  -subj "/C=RU/ST=LAB/L=LAB/O=ALDPRO/CN=mail.aldpro.lab"
sudo chmod 600 /etc/ssl/localcerts/mail.aldpro.lab.key
```

> Если используете везде имя `alddc01.aldpro.lab` — замените его в `CN` на это имя и дальше в конфиге используйте соответствующие пути.

---

## 5) Настройка Dovecot (IMAP, SASL, LMTP)

### 5.1 Расположение почты (Maildir в home)

Откройте `/etc/dovecot/conf.d/10-mail.conf`:

```conf
mail_location = maildir:~/Maildir
```

### 5.2 Аутентификация доменных пользователей (PAM/SSSD)

Откройте `/etc/dovecot/conf.d/10-auth.conf` и проверьте:

```conf
disable_plaintext_auth = yes
auth_mechanisms = plain login
!include auth-system.conf.ext
```

### 5.3 TLS для Dovecot

`/etc/dovecot/conf.d/10-ssl.conf`:

```conf
ssl = required
ssl_cert = </etc/ssl/localcerts/mail.aldpro.lab.crt
ssl_key = </etc/ssl/localcerts/mail.aldpro.lab.key
```

### 5.4 Включить IMAP + LMTP и настроить сокеты

1) Включить протоколы (файл `/etc/dovecot/dovecot.conf` или `conf.d/10-protocols.conf`):

```conf
protocols = imap lmtp
```

2) `/etc/dovecot/conf.d/10-master.conf`:

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

Перезапуск:

```bash
sudo systemctl enable --now dovecot
sudo systemctl restart dovecot
```

Проверка аутентификации доменного пользователя:

```bash
sudo doveadm auth test <domain_user> '<PASSWORD>'
```

---

## 6) Настройка Postfix (внутренняя почта + запрет внешних доменов)

### 6.1 `/etc/postfix/main.cf`

Приведите к следующему виду (подставьте выбранное имя хоста, тут — `mail.aldpro.lab`):

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

# Доставка в Dovecot по LMTP (unix-сокет)
mailbox_transport = lmtp:unix:private/dovecot-lmtp

# Включаем SMTP AUTH через Dovecot (SASL)
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes

# TLS для Postfix (самоподписанный)
smtpd_tls_cert_file=/etc/ssl/localcerts/mail.aldpro.lab.crt
smtpd_tls_key_file=/etc/ssl/localcerts/mail.aldpro.lab.key
smtpd_tls_security_level = may
smtpd_tls_auth_only = yes

# Запрещаем открытый relay, плюс жёстко ограничим доменом aldpro.lab
smtpd_recipient_restrictions =
  permit_sasl_authenticated,
  permit_mynetworks,
  reject_non_fqdn_recipient,
  reject_unknown_recipient_domain,
  check_recipient_access regexp:/etc/postfix/recipient_access,
  reject_unauth_destination

# Ограничьте "доверенные" сети (пример! замените на ваши подсети)
mynetworks = 127.0.0.0/8 [::1]/128 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12
```

> Если не уверены в `mynetworks` — оставьте только localhost, а всё остальное пусть отправляет через 587 с паролем.

### 6.1.1 Запрет отправки на внешние домены

Создайте `/etc/postfix/recipient_access`:

```conf
/^[^@]+$/            OK
/@aldpro\.lab$/      OK
/.*/                 REJECT only local mail for aldpro.lab is allowed
```

Перезагрузите Postfix:

```bash
sudo postfix reload
```

Пояснение:
- адреса **без `@`** (просто `user`) — разрешены,
- адреса `user@aldpro.lab` — разрешены,
- любые другие домены — отклоняются.

### 6.2 Включить Submission (587) в `/etc/postfix/master.cf`

Откройте `/etc/postfix/master.cf` и настройте сервис `submission`:

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

## 7) Ограничить доступ к почтовым портам до внутренних подсетей

На контроллере уже работает множество сервисов (LDAP, Kerberos, DNS и др.), поэтому аккуратнее с firewall’ом: не ломаем существующее, а **добавляем** правила для почты.

Пример через iptables (замените подсеть на вашу, например `192.168.50.0/24`):

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

> Как именно сохранять правила в Astra (iptables-persistent / nftables / механизмы ALD) — зависит от вашей конкретной политики. Если нужно, можно добавить отдельный раздел “сохранение правил” под ваш стек.

---

## 8) Проверка на контроллере

### 8.1 Порты

```bash
sudo ss -lntp | egrep ':25|:587|:993'
```

### 8.2 Логи

```bash
sudo tail -n 200 /var/log/mail.log 2>/dev/null || true
sudo journalctl -u postfix -u dovecot --no-pager -n 200
```

### 8.3 Тестовая отправка локальному доменному пользователю

```bash
echo "Test internal mail" | mail -s "hello" <domain_user>@aldpro.lab
```

Затем проверьте появление Maildir:

```bash
sudo ls -R /home/<domain_user>/Maildir 2>/dev/null || sudo ls -R ~<domain_user>/Maildir 2>/dev/null
```

---

## 9) Thunderbird на Windows (клиент в домене `aldpro.lab`)

### 9.1 Будет ли работать Thunderbird на доменном Windows-клиенте?

Да. Если рабочая станция Windows **введена в домен `aldpro.lab`**, то:
- ей будет автоматически доступен внутренний DNS ALD;
- имена `mail.aldpro.lab` и `alddc01.aldpro.lab` будут корректно резолвиться;
- пользователь входит в Windows под доменной учёткой `ALDPRO\<user>` или `<user>@ALDPRO.LAB`, что удобно логически (одна и та же учётка и для почты).

Для почты это означает:
- Thunderbird легко найдёт почтовый сервер по имени из DNS;
- логин и пароль для почты те же, что доменные (но пароль нужно ввести вручную, SSO по Kerberos в этой простой схеме не используем).

> Важно: почта в этой схеме будет работать и на **недоменных** Windows‑клиентах, если они используют DNS сервера ALD и видят порт 993/587. Но доменная рабочая станция — удобнее и предсказуемее.

### 9.2 Параметры учётной записи в Thunderbird

Создайте новую учётную запись:

- **Email**: `<domain_user>@aldpro.lab`

**Входящая почта (IMAP):**
- сервер: `mail.aldpro.lab` (или `alddc01.aldpro.lab`, если так настроили)
- порт: **993**
- безопасность соединения: **SSL/TLS**
- способ аутентификации: **Обычный пароль**
- имя пользователя: обычно `<domain_user>`

**Исходящая почта (SMTP):**
- сервер: `mail.aldpro.lab`
- порт: **587**
- безопасность соединения: **STARTTLS**
- способ аутентификации: **Обычный пароль**
- имя пользователя: `<domain_user>`

### 9.3 Предупреждение о самоподписанном сертификате

Так как сертификат самоподписанный:
- при первом подключении Thunderbird покажет предупреждение о безопасности;
- просмотрите информацию о сертификате и **подтвердите исключение**, чтобы доверять этому сертификату;
- при желании можно импортировать корневой сертификат вашей внутренней CA (если она есть) в хранилище доверенных сертификатов Windows/Thunderbird и избавиться от предупреждений.

---

## 10) Быстрый чек-лист для контроллера `alddc01.aldpro.lab`

1. **DNS**:
   - `mail.aldpro.lab -> IP alddc01.aldpro.lab`
   - `MX aldpro.lab -> mail.aldpro.lab`
2. **Доменные пользователи видны**: `getent passwd <user>` и `sudo doveadm auth test <user> '<pass>'` проходят.
3. **Порты** 25/587/993 слушаются и доступны с клиентских подсетей.
4. **Postfix** не принимает внешние домены: адреса не `@aldpro.lab` → REJECT.
5. **Thunderbird (Windows, введённый в домен)**:
   - IMAP 993 SSL/TLS, SMTP 587 STARTTLS;
   - логин `<domain_user>`, пароль доменный;
   - самоподписанный сертификат принят как исключение (или доверен через CA).


