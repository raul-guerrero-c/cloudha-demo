#!/bin/bash
set -euo pipefail

# CloudHA Manager - Inicializacion automatica EC2
# Region: us-east-1

export AWS_DEFAULT_REGION=us-east-1

echo "CloudHA: iniciando configuracion de instancia"

# 1. Instalar dependencias
dnf install -y python3 python3-pip git

# AWS CLI esta disponible en la AMI utilizada
command -v aws >/dev/null || {
    echo "ERROR: AWS CLI no esta disponible"
    exit 1
}

# 2. Descargar aplicacion
mkdir -p /opt/cloudha

git clone --branch main --depth 1 \
  https://github.com/raul-guerrero-c/cloudha-demo.git \
  /opt/cloudha/app

# 3. Preparar entorno Python
cd /opt/cloudha/app

python3 -m venv .venv

.venv/bin/pip install -r requirements.txt

chown -R ec2-user:ec2-user /opt/cloudha

# 4. Crear directorio seguro de configuracion
install -d -o root -g ec2-user -m 750 /etc/cloudha

# 5. Crear script para recuperar parametros desde SSM
cat > /usr/local/sbin/cloudha-load-config.py <<'PY'
#!/usr/bin/env python3

import grp
import json
import os
import subprocess
import tempfile

REGION = "us-east-1"
PREFIX = "/cloudha/prod/"

NAMES = [
    "DB_HOST",
    "DB_NAME",
    "DB_USER",
    "DB_PASSWORD",
]

# Obtener los parametros, incluida la clave cifrada
result = subprocess.run(
    [
        "aws", "ssm", "get-parameters",
        "--names",
        *[PREFIX + name for name in NAMES],
        "--with-decryption",
        "--region", REGION,
        "--output", "json",
    ],
    check=True,
    capture_output=True,
    text=True,
)

response = json.loads(result.stdout)

if response.get("InvalidParameters"):
    raise RuntimeError("Faltan parametros de CloudHA")

values = {
    item["Name"].removeprefix(PREFIX): item["Value"]
    for item in response["Parameters"]
}

if set(values) != set(NAMES):
    raise RuntimeError("Configuracion de RDS incompleta")

# Validar y escapar los valores para systemd
def systemd_value(value):
    if any(char in value for char in "\r\n\x00"):
        raise ValueError("Valor de configuracion no valido")

    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'

directory = "/etc/cloudha"

os.makedirs(directory, exist_ok=True)

fd, temporary_path = tempfile.mkstemp(
    prefix=".cloudha-",
    dir=directory,
)

try:
    os.fchmod(fd, 0o600)

    with os.fdopen(fd, "w", encoding="utf-8") as output:
        for name in NAMES:
            output.write(
                f"{name}={systemd_value(values[name])}\n"
            )

    os.chown(
        temporary_path,
        0,
        grp.getgrnam("ec2-user").gr_gid,
    )

    os.chmod(temporary_path, 0o640)

    os.replace(
        temporary_path,
        "/etc/cloudha/cloudha.env",
    )

except Exception:
    if os.path.exists(temporary_path):
        os.unlink(temporary_path)
    raise

print("CloudHA: configuracion RDS disponible")
PY

chmod 700 /usr/local/sbin/cloudha-load-config.py

# 6. Recuperar las credenciales antes de iniciar Flask
python3 /usr/local/sbin/cloudha-load-config.py

# 7. Crear servicio systemd
cat > /etc/systemd/system/cloudha.service <<'EOF'
[Unit]
Description=CloudHA Manager - Flask Application
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ec2-user
Group=ec2-user
WorkingDirectory=/opt/cloudha/app
EnvironmentFile=/etc/cloudha/cloudha.env
ExecStart=/opt/cloudha/app/.venv/bin/gunicorn --workers 2 --bind 0.0.0.0:8080 app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 8. Habilitar e iniciar Flask
systemctl daemon-reload
systemctl enable cloudha
systemctl start cloudha

# 9. Comprobar inicio
systemctl is-active --quiet cloudha

echo "CloudHA: inicializacion completada"