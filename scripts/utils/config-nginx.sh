#!/bin/bash

#
# Install packages
apt-get update
apt install -y nginx

#
# Deployment

##########################
###Variable à modifier!###
##########################
host_ip=$(ss-get hostname)

openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/nginx-selfsigned.key -out /etc/ssl/certs/nginx-selfsigned.crt -subj "/C=FR/ST=Lyon/L=Lyon/O=IFB/OU=IFB-core/CN=134.158.247.60"
openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048
mkdir -p /etc/nginx/snippets
echo "ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;" > /etc/nginx/snippets/self-signed.conf
echo "ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;" >> /etc/nginx/snippets/self-signed.conf

cat > /etc/nginx/snippets/ssl-params.conf << "EOF"
ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
ssl_prefer_server_ciphers on;
ssl_ciphers "EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH";
ssl_ecdh_curve secp384r1;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;
# Disable preloading HSTS for now.  You can use the commented out header line that includes
# the "preload" directive if you understand the implications.
#add_header Strict-Transport-Security "max-age=63072000; includeSubdomains; preload";
add_header Strict-Transport-Security "max-age=63072000; includeSubdomains";
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;

ssl_dhparam /etc/ssl/certs/dhparam.pem;
EOF

cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
cat > /etc/nginx/sites-available/default << "EOF"
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name server_domain_or_IP;
    return 301 https://$server_name$request_uri;
}

server {

    # SSL configuration

    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    include snippets/self-signed.conf;
    include snippets/ssl-params.conf;
    root /var/www/html;

    # Add index.php to the list if you are using PHP
    index index.html index.htm index.nginx-debian.html;

    server_name _;

    location / {
            # First attempt to serve request as file, then
            # as directory, then fall back to displaying a 404.
            try_files $uri $uri/ =404;
    }
}
EOF
sed -i "s|server_domain_or_IP|$host_ip|"  /etc/nginx/sites-available/default

useradd nginx
cat > /etc/nginx/nginx.conf << "EOF"
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;
include /usr/share/nginx/modules/*.conf;
events {
worker_connections 1024;
}
http {
log_format main '$remote_addr - $remote_user [$time_local] "$request" '
'$status $body_bytes_sent "$http_referer" '
'"$http_user_agent" "$http_x_forwarded_for"';
access_log /var/log/nginx/access.log main;
sendfile on;
tcp_nopush on;
tcp_nodelay on;
keepalive_timeout 65;
types_hash_max_size 2048;
include /etc/nginx/mime.types;
default_type application/octet-stream;
# Load modular configuration files from the /etc/nginx/conf.d directory.
# See http://nginx.org/en/docs/ngx_core_module.html#include
# for more information.
include /etc/nginx/conf.d/*.conf;
client_max_body_size 0;
}
EOF


#############################################################
###fichier suivant à modifier selon l'application utilisée###
#############################################################

cat > /etc/nginx/conf.d/my-site.conf << "EOF"
server {
listen 80;
listen [::]:80;
server_name example.com;
return 301 https://$server_name$request_uri;
}
server {
listen 443 ssl http2;
listen [::]:443 ssl http2;
include snippets/self-signed.conf;
include snippets/ssl-params.conf;
location / {
proxy_pass http://localhost:8080/;
proxy_redirect http://localhost:8080/ $scheme://$host/;
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_set_header Host $host;
}
}
EOF
sed -i "s|example.com|$host_ip|" /etc/nginx/conf.d/my-site.conf

systemctl restart nginx
systemctl enable nginx
echo "Nginx configured."