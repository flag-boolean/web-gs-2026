## Развертывание веб-стендов (Ubuntu) — справочник

Этот проект поднимает несколько контейнеров `nginx:alpine`, каждый отдает статический сайт из своей папки `teams/<N>` по HTTP.

### Что нужно разместить на сервере

На сервере должны оказаться **минимум**:
- `docker-compose.yml`
- папка `teams/` (внутри `teams/1`, `teams/2`, … с файлами `index.html`, `style.css`, `app.js`, `fonts/`, `svg/` и т.д.)

Рекомендуемая структура на сервере:

```text
/opt/GS_CORPA_26/
  docker-compose.yml
  teams/
    1/
    2/
    3/
    ...
```

### Установка Docker и Docker Compose (Ubuntu)

Установите Docker Engine и Compose plugin (официальные пакеты):

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Проверьте версии:

```bash
docker --version
docker compose version
```

Опционально (чтобы запускать без `sudo`):

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

### Запуск стендов

Перейдите в папку проекта на сервере (там где лежит `docker-compose.yml`) и запустите:

```bash
docker compose up -d
```

Остановить:

```bash
docker compose down
```

Перезапустить (после изменений в `teams/` обычно достаточно перезагрузки браузера, но можно так):

```bash
docker compose restart
```

### Что проверить после запуска

- **Контейнеры поднялись**:

```bash
docker compose ps
```

- **Логи nginx** (если что-то не отдается):

```bash
docker compose logs --tail=200 -f
```

- **Пути volume**:
  - В `docker-compose.yml` папки монтируются как `./teams/<N>:/usr/share/nginx/html:ro`
  - Значит важно запускать `docker compose ...` **из той же директории**, где лежат `docker-compose.yml` и `teams/`.

- **IP-адреса/привязка портов**:
  - В `docker-compose.yml` порты заданы так: `"172.xx.30.254:80:80"`.
  - Эти IP **должны существовать на сетевом интерфейсе сервера**, иначе Docker выдаст ошибку биндинга.
  - Проверка IP на сервере:

```bash
ip a
```

Если таких IP нет — используйте обычную привязку к порту (пример: `"8081:80"`, `"8082:80"` …) или привязку к `0.0.0.0:80:80` (если нужен один сервис).

- **Firewall**:
  - Для доступа извне убедитесь, что порт 80 (или ваши host-порты) открыт в `ufw`/security group.

### Быстрый тест доступности

Пример (подставьте нужный IP из compose):

```bash
curl -I http://172.21.30.254/
```

### Частые проблемы

- **`bind: cannot assign requested address`**: на сервере нет IP, указанного в `ports`.
- **404/пустая страница**: в `teams/<N>` нет `index.html` или не та папка смонтирована (запустили compose из другой директории).
- **Изменения не видны**: браузер кэширует — сделайте hard reload или откройте в приватном окне.
