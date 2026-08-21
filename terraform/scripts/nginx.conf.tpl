server {
    listen 80;

    location / {
        proxy_pass http://${app_private_ip}:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
