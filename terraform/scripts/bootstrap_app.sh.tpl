#!/bin/bash
set -e

apt-get update
apt-get install -y python3-pip curl gnupg unixodbc unixodbc-dev

curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg
curl https://packages.microsoft.com/config/ubuntu/24.04/prod.list | tee /etc/apt/sources.list.d/mssql-release.list
apt-get update
ACCEPT_EULA=Y apt-get install -y msodbcsql18

pip3 install --break-system-packages flask pyodbc azure-identity azure-keyvault-secrets

mkdir -p /opt/app
cat > /opt/app/app.py << 'PYEOF'
${app_py_content}
PYEOF

cat > /opt/app/app.env << ENVEOF
KEY_VAULT_URI=${key_vault_uri}
SQL_SERVER_FQDN=${sql_server_fqdn}
SQL_DATABASE=${sql_database}
ENVEOF

cat > /etc/systemd/system/flaskapp.service << 'EOF'
[Unit]
Description=Flask App - 3-Tier Lab
After=network.target

[Service]
EnvironmentFile=/opt/app/app.env
ExecStart=/usr/bin/python3 /opt/app/app.py
Restart=always
User=azureuser

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable flaskapp
systemctl start flaskapp
