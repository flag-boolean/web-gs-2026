# Монтирование сетевой папки DISTRIB

## Предварительно на Windows Server

Создать папку `DISTRIB` с общим доступом (SMB/CIFS) с разрешениями для всех пользователей и гостей.
**Аналогичный способ создать общую папку Предприятия с общим доступом.** 

## Инструкция для Linux

### 1. Установка необходимых пакетов

```bash
sudo apt update
sudo apt install cifs-utils
```

### 2. Создание точки монтирования

```bash
sudo mkdir -p /mnt/DISTRIB
sudo chmod 755 /mnt/DISTRIB
```

### 3. Создание файла с учетными данными

```bash
sudo install -m 600 /dev/null /etc/samba/creds-shared-ro
sudo nano /etc/samba/creds-shared-ro
```

Добавить содержимое:
```
username=guest
password=
```

### 4. Добавление записи в fstab

Заменить `IPADDRESS` на реальный IP-адрес сервера Windows:

```bash
echo '//IPADDRESS/DISTRIB  /mnt/DISTRIB  cifs  credentials=/etc/samba/creds-shared-ro,vers=3.1.1,uid=1000,gid=1000,file_mode=0660,dir_mode=0770,nofail,x-systemd.automount  0  0' | sudo tee -a /etc/fstab
```

### 5. Применение настроек

```bash
sudo mount -a
```

### 6. Проверка монтирования

```bash
df -h | grep DISTRIB
ls -la /mnt/DISTRIB
```

