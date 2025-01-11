#!/bin/bash

PASSWORD="q1w2e3r4t5y6"
MYSQL_PASSWORD="root"
IP=$(hostname -I | awk '{print $1}') # Получаем локальный IP
APACHE_LOG_DIR=/var/log/apache2
DOMAIN="my_freehost.local"

# Обновление пакетов и установка зависимостей
sudo apt update
sudo apt install -y apache2 mysql-server php libapache2-mod-php php-curl php-gd php-intl php-mbstring php-soap php-xml php-zip php-mysql php-cli nginx wget

# Настройка MySQL
sudo mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$PASSWORD';"
sudo mysql -u root -e "FLUSH PRIVILEGES;"
sudo mysql -u root -p"$PASSWORD" -e "CREATE DATABASE wp_db DEFAULT CHARACTER SET utf8;"
sudo mysql -u root -p"$PASSWORD" -e "CREATE USER 'wp_user'@'localhost' IDENTIFIED BY '$PASSWORD';"
sudo mysql -u root -p"$PASSWORD" -e "GRANT ALL PRIVILEGES ON wp_db.* TO 'wp_user'@'localhost';"
sudo mysql -u root -p"$PASSWORD" -e "FLUSH PRIVILEGES;"

# Установка WordPress
wget -c https://wordpress.org/latest.tar.gz
sudo tar -xzf latest.tar.gz -C /var/www/html --strip-components=1
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html
sudo rm -f /var/www/html/index.html

# Включение необходимых модулей Apache
sudo a2enmod proxy proxy_fcgi setenvif
sudo mkdir -p $APACHE_LOG_DIR

# === Изменяем ports.conf ===
# Удаляем существующие строки "Listen 80" и добавляем "Listen 8080"
sudo sed -i '/Listen 80/d' /etc/apache2/ports.conf
echo "Listen 8080" | sudo tee -a /etc/apache2/ports.conf > /dev/null

# === Создаем виртуальный хост для Apache (порт 8080) ===
cat <<EOF | sudo tee /etc/apache2/sites-available/wordpress.conf > /dev/null
<VirtualHost *:8080>
    ServerName $DOMAIN
    DocumentRoot /var/www/html

    <Directory /var/www/html>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

# Активируем сайт и перезапускаем Apache
sudo a2ensite wordpress.conf
sudo systemctl restart apache2

# === Добавляем IP и домен в /etc/hosts ===
if ! grep -q "$DOMAIN" /etc/hosts; then
    echo "$IP $DOMAIN" | sudo tee -a /etc/hosts > /dev/null
    echo "Добавлено: $IP $DOMAIN в /etc/hosts"
else
    echo "Домен $DOMAIN уже есть в /etc/hosts"
fi

# === Создаем конфигурацию Nginx (порт 80, прокси на Apache) ===
cat <<EOF | sudo tee /etc/nginx/sites-available/wordpress.conf > /dev/null
server {
    listen 80;
    server_name $DOMAIN;

    root /var/www/html;
    index index.php index.html index.htm;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location ~ \.php\$ {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg|eot)\$ {
        expires max;
        log_not_found off;
    }
}
EOF

# Включаем конфигурацию Nginx и перезапускаем
sudo ln -s /etc/nginx/sites-available/wordpress.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl restart nginx