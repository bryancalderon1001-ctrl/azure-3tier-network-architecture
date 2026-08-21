#!/bin/bash
set -e

apt-get update
apt-get install -y nginx

cat > /etc/nginx/sites-available/default << 'NGINXEOF'
${nginx_config}
NGINXEOF

systemctl restart nginx
systemctl enable nginx
