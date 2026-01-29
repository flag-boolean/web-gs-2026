## WireGuard на Ubuntu — справочник (7 интерфейсов, изоляция по командам)

Задача: поднять WireGuard на сервере Ubuntu так, чтобы:
- был **1 “общий/админский” интерфейс** (доступ по белому IP сервера);
- было **6 интерфейсов под команды**, каждая команда получает доступ **только** к своему веб-стенду (IP из `docker-compose.yml`):
  - team1 → `172.21.30.254:80`
  - team2 → `172.22.30.254:80`
  - team3 → `172.23.30.254:80`
  - team4 → `172.24.30.254:80`
  - team5 → `172.25.30.254:80`
  - team6 → `172.26.30.254:80`

Также: после открытия веба на `...254` участнику нужно ходить по **всем портам к другим серверам в этой же /24 подсети** (например, `172.21.30.0/24` для team1).

Важно (под ваш сценарий):
- доступ к `172.xx.30.254:80` — это **INPUT** (nginx/docker на самом WireGuard-сервере);
- доступ к “другим серверам” в `172.xx.30.0/24` — это **FORWARD** (это отдельные ВМ не на этом сервере), и обычно нужен **MASQUERADE**.

---

### Предусловия (перед настройкой)

- На сервере уже развернуты стенды через `docker-compose.yml`.
- У сервера есть **белый IP** (или проброс UDP-порта на него).
- Открыты UDP-порты WireGuard (ниже приведены порты по умолчанию).

Проверить IP на сервере:

```bash
ip a
```

---

### Установка WireGuard (Ubuntu)

```bash
sudo apt-get update
sudo apt-get install -y wireguard iptables iptables-persistent
```

Примечание:
- На Ubuntu `iptables` часто работает через backend `iptables-nft` — это нормально, команды `iptables` остаются теми же.
- `iptables-persistent` может спросить про сохранение текущих правил. Если ставите на “чистый” сервер — можно согласиться.

Включить форвардинг (на всякий случай; для доступа к локальным IP может не потребоваться, но полезно для расширения сценариев):

```bash
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-wireguard.conf
sudo sysctl --system
```

---

### План интерфейсов и портов

Мы поднимем 7 интерфейсов:
- `wg0` — admin (можно дать доступ шире, если нужно)
- `wg1` — team1 (доступ только к `172.21.30.254:80`)
- `wg2` — team2 (доступ только к `172.22.30.254:80`)
- `wg3` — team3 (доступ только к `172.23.30.254:80`)
- `wg4` — team4 (доступ только к `172.24.30.254:80`)
- `wg5` — team5 (доступ только к `172.25.30.254:80`)
- `wg6` — team6 (доступ только к `172.26.30.254:80`)

Порты (можно менять, главное открыть на firewall/NAT):
- `wg0`: UDP `51820`
- `wg1..wg6`: UDP `51821..51826`

VPN-адреса (внутренние, не пересекаются с вашими `172.xx`):
- `wg0`: `10.200.0.1/24`
- `wg1`: `10.201.1.1/24`
- `wg2`: `10.201.2.1/24`
- `wg3`: `10.201.3.1/24`
- `wg4`: `10.201.4.1/24`
- `wg5`: `10.201.5.1/24`
- `wg6`: `10.201.6.1/24`

---

### Генерация ключей сервера

```bash
sudo -i
umask 077
mkdir -p /etc/wireguard/keys

wg genkey | tee /etc/wireguard/keys/server.key | wg pubkey > /etc/wireguard/keys/server.pub
exit
```

---

### Фаервол: изоляция “команда → только свой IP”

Сделаем правила iptables:
- разрешаем **входящие** TCP/80 на конкретный `172.xx.30.254` **только** с нужного `wgX`;
- разрешаем **все** только в **свою подсеть /24** (например, team1 → `172.21.30.0/24`) через **FORWARD**;
- для `wg1..wg6` **запрещаем остальной входящий трафик** (чтобы не было доступа к другим адресам сервера/стендов);
- разрешаем handshakes WireGuard по UDP-портам.

Применить правила (выполняйте от root/через sudo):

```bash
# 1) Базовое: established + loopback
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A INPUT -i lo -j ACCEPT

# 2) WireGuard handshake (UDP порты)
sudo iptables -A INPUT -p udp -m multiport --dports 51820,51821,51822,51823,51824,51825,51826 -j ACCEPT

# 3) Доступ к стендам только со своего wg-интерфейса (HTTP/80)
sudo iptables -A INPUT -i wg1 -d 172.21.30.254 -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -i wg2 -d 172.22.30.254 -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -i wg3 -d 172.23.30.254 -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -i wg4 -d 172.24.30.254 -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -i wg5 -d 172.25.30.254 -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -i wg6 -d 172.26.30.254 -p tcp --dport 80 -j ACCEPT

# 4) Запрет "лишнего" трафика с team интерфейсов
sudo iptables -A INPUT -i wg1 -j DROP
sudo iptables -A INPUT -i wg2 -j DROP
sudo iptables -A INPUT -i wg3 -j DROP
sudo iptables -A INPUT -i wg4 -j DROP
sudo iptables -A INPUT -i wg5 -j DROP
sudo iptables -A INPUT -i wg6 -j DROP
```

#### Доступ к “другим серверам” (отдельные ВМ) — нужен FORWARD + MASQUERADE

В вашем случае хосты `172.xx.30.0/24` — это **отдельные машины** (не WireGuard-сервер), поэтому:
- трафик из VPN пойдёт через **FORWARD**
- почти всегда нужен **MASQUERADE**, чтобы этим ВМ не нужно было прописывать маршрут обратно в `10.201.x.0/24`

1) Узнайте интерфейс выхода в “лабораторную” сеть (пример: `eth1`):

```bash
ip route | grep 172.21.30.0/24
```

2) Разрешите форвардинг только в свою подсеть:

```bash
# Разрешаем established
sudo iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Team1: wg1 -> 172.21.30.0/24 (SSH/RDP)
sudo iptables -A FORWARD -i wg1 -d 172.21.30.0/24 -p tcp -j ACCEPT
# Team2..Team6:
sudo iptables -A FORWARD -i wg2 -d 172.22.30.0/24 -p tcp -j ACCEPT
sudo iptables -A FORWARD -i wg3 -d 172.23.30.0/24 -p tcp -j ACCEPT
sudo iptables -A FORWARD -i wg4 -d 172.24.30.0/24 -p tcp -j ACCEPT
sudo iptables -A FORWARD -i wg5 -d 172.25.30.0/24 -p tcp -j ACCEPT
sudo iptables -A FORWARD -i wg6 -d 172.26.30.0/24 -p tcp -j ACCEPT

# Запрещаем остальное с team интерфейсов
sudo iptables -A FORWARD -i wg1 -j DROP
sudo iptables -A FORWARD -i wg2 -j DROP
sudo iptables -A FORWARD -i wg3 -j DROP
sudo iptables -A FORWARD -i wg4 -j DROP
sudo iptables -A FORWARD -i wg5 -j DROP
sudo iptables -A FORWARD -i wg6 -j DROP
```

3) SNAT (если у целевых машин нет маршрута обратно в `10.201.x.0/24`):

```bash
# Замените eth1 на ваш интерфейс в сторону 172.xx.30.0/24
OUT_IF="eth1"

sudo iptables -t nat -A POSTROUTING -s 10.201.1.0/24 -o "$OUT_IF" -d 172.21.30.0/24 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -s 10.201.2.0/24 -o "$OUT_IF" -d 172.22.30.0/24 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -s 10.201.3.0/24 -o "$OUT_IF" -d 172.23.30.0/24 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -s 10.201.4.0/24 -o "$OUT_IF" -d 172.24.30.0/24 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -s 10.201.5.0/24 -o "$OUT_IF" -d 172.25.30.0/24 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -s 10.201.6.0/24 -o "$OUT_IF" -d 172.26.30.0/24 -j MASQUERADE
```

Проверить порядок правил:

```bash
sudo iptables -S INPUT
sudo iptables -L INPUT -n -v --line-numbers
```

Сохранить правила, чтобы пережили перезагрузку:

```bash
sudo netfilter-persistent save
sudo systemctl enable --now netfilter-persistent
```

---

### Конфиги WireGuard интерфейсов (server)

Создайте `/etc/wireguard/wg0.conf`:

```ini
[Interface]
Address = 10.200.0.1/24
ListenPort = 51820
PrivateKey = <SERVER_PRIVATE_KEY>

# Опционально: чтобы wg быстро поднимался
SaveConfig = false
```

Создайте `/etc/wireguard/wg1.conf` … `/etc/wireguard/wg6.conf` по шаблону (пример для `wg1`):

```ini
[Interface]
Address = 10.201.1.1/24
ListenPort = 51821
PrivateKey = <SERVER_PRIVATE_KEY>
SaveConfig = false
```

Примечание: можно использовать **один и тот же** серверный ключ для всех интерфейсов (как выше), либо сгенерировать отдельные ключи на каждый интерфейс — оба варианта рабочие. Для простоты — один ключ.

Подставить приватный ключ в конфиги:

```bash
sudo sed -i "s#<SERVER_PRIVATE_KEY>#$(sudo cat /etc/wireguard/keys/server.key)#g" /etc/wireguard/wg{0,1,2,3,4,5,6}.conf
```

Запуск интерфейсов:

```bash
sudo systemctl enable --now wg-quick@wg0
sudo systemctl enable --now wg-quick@wg1
sudo systemctl enable --now wg-quick@wg2
sudo systemctl enable --now wg-quick@wg3
sudo systemctl enable --now wg-quick@wg4
sudo systemctl enable --now wg-quick@wg5
sudo systemctl enable --now wg-quick@wg6
```

Проверка:

```bash
sudo wg show
ip a | grep -E "wg[0-6]"
```

---

### Создание конфигов пользователей (clients) — доступ строго к своему стенду

#### 1) Сгенерировать ключи пользователя

Пример: пользователь `team1-user1` (интерфейс `wg1`):

```bash
sudo -i
umask 077
mkdir -p /etc/wireguard/clients/team1-user1

wg genkey | tee /etc/wireguard/clients/team1-user1/client.key | wg pubkey > /etc/wireguard/clients/team1-user1/client.pub
exit
```

#### 2) Добавить peer на сервер (в нужный wg-интерфейс)

Выдаем пользователю VPN-IP (например) `10.201.1.10/32` на интерфейсе `wg1`:

```bash
PUB="$(sudo cat /etc/wireguard/clients/team1-user1/client.pub)"
sudo wg set wg1 peer "$PUB" allowed-ips 10.201.1.10/32
```

Чтобы переживало перезагрузку — добавьте peer секцию в `/etc/wireguard/wg1.conf`:

```ini
[Peer]
PublicKey = <TEAM1_USER1_PUB>
AllowedIPs = 10.201.1.10/32
```

И перезапустите интерфейс:

```bash
sudo systemctl restart wg-quick@wg1
```

#### 3) Сформировать клиентский конфиг

Клиент должен “маршрутизировать” только **свою подсеть /24** (включая `.254` с вебом и остальные хосты, куда нужно ходить по SSH).

`team1-user1.conf`:

```ini
[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address = 10.201.1.10/32
DNS = 1.1.1.1

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
Endpoint = <SERVER_PUBLIC_IP>:51821
AllowedIPs = 172.21.30.0/24
PersistentKeepalive = 25
```

Где:
- `<SERVER_PUBLIC_IP>` — белый IP сервера (или домен)
- `AllowedIPs = 172.21.30.0/24` — ключевой момент: клиент “видит” только свою /24 подсеть
- Порт `51821` соответствует `wg1`

Серверный public key:

```bash
sudo cat /etc/wireguard/keys/server.pub
```

Клиентский private key:

```bash
sudo cat /etc/wireguard/clients/team1-user1/client.key
```

По аналогии делаются конфиги для team2..team6, только:
- Endpoint порт: `51822..51826`
- AllowedIPs: `172.22.30.0/24` … `172.26.30.0/24`
- VPN Address: `10.201.2.x/32` … `10.201.6.x/32`

---

### Проверка доступа (на сервере и у клиента)

На сервере:

```bash
sudo wg show
sudo ss -lunp | grep 5182
```

На клиенте после подключения:

```bash
curl -I http://172.21.30.254/
# Пример SSH проверки (если в подсети есть SSH-хост):
# ssh user@172.21.30.10
```

Проверка изоляции: клиент team1 **не должен** иметь доступ к `172.22.30.0/24` (например, `172.22.30.254`) и т.д.

---

### Что чаще всего ломается

- **Не открыт UDP порт** (на сервере/в облаке/на NAT): нет handshakes.
- **Неправильный `Endpoint`**: должен быть белый IP сервера и порт конкретного `wgX`.
- **Нет IP на сервере `172.xx.30.254`**: тогда nginx bind не поднимется и доступ не будет работать.
- **Фаервол режет INPUT**: проверьте `iptables -L INPUT -n -v --line-numbers` и логи.


