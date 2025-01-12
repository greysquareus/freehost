#!/bin/bash

###Last version###

PASSWORD="q1w2e3r4t5y6"
MYSQL_PASSWORD="root"
IP=$(hostname -I | awk '{print $1}')
APACHE_LOG_DIR=/var/log/apache2
DOMAIN="my_freehost.local"

sudo apt update
sudo apt install -y apache2 mysql-server php libapache2-mod-php php-curl php-gd php-intl php-mbstring php-soap php-xml php-zip php-mysql php-cli nginx wget php-fpm

sudo mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$PASSWORD';"
sudo mysql -u root -e "FLUSH PRIVILEGES;"
sudo mysql -u root -p"$PASSWORD" -e "CREATE DATABASE wp_db DEFAULT CHARACTER SET utf8;"
sudo mysql -u root -p"$PASSWORD" -e "CREATE USER 'wp_user'@'localhost' IDENTIFIED BY '$PASSWORD';"
sudo mysql -u root -p"$PASSWORD" -e "GRANT ALL PRIVILEGES ON wp_db.* TO 'wp_user'@'localhost';"
sudo mysql -u root -p"$PASSWORD" -e "FLUSH PRIVILEGES;"

wget -c https://wordpress.org/latest.tar.gz
sudo tar -xzf latest.tar.gz -C /var/www/html --strip-components=1
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html
sudo rm -f /var/www/html/index.html

sudo a2enmod proxy proxy_fcgi setenvif
sudo mkdir -p $APACHE_LOG_DIR

sudo sed -i '/Listen 80/d' /etc/apache2/ports.conf
sudo sed -i '5i Listen 8080' /etc/apache2/ports.conf

cat <<EOF | sudo tee /etc/apache2/sites-available/wordpress.conf > /dev/null
<VirtualHost *:8080>
    ServerName $DOMAIN
    DocumentRoot /var/www/html

    <Directory /var/www/html>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \$APACHE_LOG_DIR/error.log
    CustomLog \$APACHE_LOG_DIR/access.log combined
</VirtualHost>
EOF

sudo a2ensite wordpress.conf
sudo systemctl restart apache2

if ! grep -q "$DOMAIN" /etc/hosts; then
    sed -i 'i1 $IP $DOMAIN'
    echo "Добавлено: $IP $DOMAIN в /etc/hosts"
else
    echo "Домен $DOMAIN уже есть в /etc/hosts"
fi

cat <<EOF | sudo tee /etc/nginx/sites-available/wordpress.conf > /dev/null
server {
    listen 80;
    server_name my_freehost.com;

    root /var/www/html;
    index index.php index.html index.htm;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}


EOF

sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -s /etc/nginx/sites-available/wordpress.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl restart nginx
