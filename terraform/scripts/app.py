from flask import Flask, jsonify
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
import pyodbc
import os

app = Flask(__name__)

KEY_VAULT_URI  = os.environ["KEY_VAULT_URI"]
SQL_SERVER     = os.environ["SQL_SERVER_FQDN"]
SQL_DATABASE   = os.environ["SQL_DATABASE"]
SQL_ADMIN_USER = os.environ.get("SQL_ADMIN_USER", "azureuser")
SECRET_NAME    = "sql-admin-password"

credential = DefaultAzureCredential()
secret_client = SecretClient(vault_url=KEY_VAULT_URI, credential=credential)


def get_db_connection():
    password = secret_client.get_secret(SECRET_NAME).value
    conn_str = (
        f"Driver={{ODBC Driver 18 for SQL Server}};"
        f"Server=tcp:{SQL_SERVER},1433;"
        f"Database={SQL_DATABASE};"
        f"Uid={SQL_ADMIN_USER};"
        f"Pwd={password};"
        f"Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
    )
    return pyodbc.connect(conn_str)


@app.route("/health")
def health():
    return jsonify(status="ok"), 200


@app.route("/db-check")
def db_check():
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.fetchone()
        conn.close()
        return jsonify(status="connected"), 200
    except Exception as e:
        return jsonify(status="error", detail=str(e)), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
