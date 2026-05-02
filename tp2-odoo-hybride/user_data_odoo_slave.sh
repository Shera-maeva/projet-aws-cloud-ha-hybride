#!/bin/bash
###############################################################################
# Script user_data pour EC2 Odoo - Noeud SLAVE/REPLICA
# Installe Docker + Odoo + PostgreSQL (Bucardo se branche depuis le master)
#
# IMPORTANT: tous les $ du bash sont echappes en $$ pour Terraform templatefile
###############################################################################

set -e
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "===== Demarrage de l installation Odoo SLAVE ====="

# -----------------------------------------------------------------------------
# Variables (injectees par Terraform via templatefile)
# -----------------------------------------------------------------------------
NODE_NAME="${node_name}"
NODE_ROLE="slave"
PEER_PRIVATE_IP="${peer_private_ip}"
ODOO_VERSION="${odoo_version}"
POSTGRES_VERSION="${postgres_version}"
POSTGRES_PASSWORD="${postgres_password}"
ODOO_ADMIN_PASSWORD="${odoo_admin_password}"
BUCARDO_PASSWORD="${bucardo_password}"

# -----------------------------------------------------------------------------
# Mise a jour systeme
# -----------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y curl wget gnupg lsb-release ca-certificates apt-transport-https \
    awscli jq postgresql-client netcat-openbsd

# -----------------------------------------------------------------------------
# Installation Docker
# -----------------------------------------------------------------------------
echo "===== Installation de Docker ====="
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $$(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
apt-get install -y docker-compose

systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# -----------------------------------------------------------------------------
# Recuperation IP privee
# -----------------------------------------------------------------------------
TOKEN=$$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
LOCAL_IP=$$(curl -s -H "X-aws-ec2-metadata-token: $$TOKEN" \
    http://169.254.169.254/latest/meta-data/local-ipv4)
INSTANCE_ID=$$(curl -s -H "X-aws-ec2-metadata-token: $$TOKEN" \
    http://169.254.169.254/latest/meta-data/instance-id)
AZ=$$(curl -s -H "X-aws-ec2-metadata-token: $$TOKEN" \
    http://169.254.169.254/latest/meta-data/placement/availability-zone)

echo "Local IP: $$LOCAL_IP, Peer (master) IP: $$PEER_PRIVATE_IP, AZ: $$AZ"

# -----------------------------------------------------------------------------
# Creation arborescence Odoo
# -----------------------------------------------------------------------------
mkdir -p /opt/odoo/config /opt/odoo/addons /opt/odoo/postgresql-data
cd /opt/odoo

# Configuration Odoo
cat > /opt/odoo/config/odoo.conf <<EOF
[options]
admin_passwd = $$ODOO_ADMIN_PASSWORD
db_host = db
db_port = 5432
db_user = odoo
db_password = $$POSTGRES_PASSWORD
addons_path = /mnt/extra-addons
data_dir = /var/lib/odoo
proxy_mode = True
log_level = info
EOF

cat > /opt/odoo/postgresql.conf <<'PGEOF'
listen_addresses = '*'
max_connections = 200
shared_buffers = 256MB
wal_level = logical
max_wal_senders = 10
max_replication_slots = 10
PGEOF

cat > /opt/odoo/pg_hba.conf <<'HBAEOF'
local   all             all                                     trust
host    all             all             127.0.0.1/32            md5
host    all             all             0.0.0.0/0               md5
host    replication     all             0.0.0.0/0               md5
HBAEOF

cat > /opt/odoo/docker-compose.yml <<EOF
services:
  db:
    image: postgres:$$POSTGRES_VERSION
    container_name: odoo-db
    restart: always
    environment:
      POSTGRES_DB: postgres
      POSTGRES_USER: odoo
      POSTGRES_PASSWORD: $$POSTGRES_PASSWORD
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - ./postgresql-data:/var/lib/postgresql/data/pgdata
      - ./postgresql.conf:/etc/postgresql/postgresql.conf
      - ./pg_hba.conf:/etc/postgresql/pg_hba.conf
    command:
      - "postgres"
      - "-c"
      - "config_file=/etc/postgresql/postgresql.conf"
      - "-c"
      - "hba_file=/etc/postgresql/pg_hba.conf"
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U odoo"]
      interval: 10s
      timeout: 5s
      retries: 5

  odoo:
    image: odoo:$$ODOO_VERSION
    container_name: odoo-app
    restart: always
    depends_on:
      db:
        condition: service_healthy
    ports:
      - "8069:8069"
      - "8072:8072"
    volumes:
      - ./config:/etc/odoo
      - ./addons:/mnt/extra-addons
      - odoo-data:/var/lib/odoo
    environment:
      HOST: db
      USER: odoo
      PASSWORD: $$POSTGRES_PASSWORD

volumes:
  odoo-data:
EOF

chmod -R 755 /opt/odoo
chown -R 1000:1000 /opt/odoo/addons /opt/odoo/config

# Demarrage stack
echo "===== Demarrage des conteneurs ====="
cd /opt/odoo
docker compose pull
docker compose up -d

# Attente Postgres
for i in {1..60}; do
    if docker exec odoo-db pg_isready -U odoo > /dev/null 2>&1; then
        echo "PostgreSQL pret!"
        break
    fi
    sleep 5
done

# Attente Odoo
for i in {1..60}; do
    if curl -s http://localhost:8069 > /dev/null 2>&1; then
        echo "Odoo pret!"
        break
    fi
    sleep 5
done

# Creation BDD odoo
sleep 30
docker exec odoo-db psql -U odoo -d postgres -c "CREATE DATABASE odoo OWNER odoo;" || true

# Pre-creation user bucardo (le master en aura besoin pour la replication)
docker exec odoo-db psql -U odoo -d postgres -c "CREATE USER bucardo WITH SUPERUSER PASSWORD '$$BUCARDO_PASSWORD';" || true

# -----------------------------------------------------------------------------
# Fichier d info
# -----------------------------------------------------------------------------
cat > /home/ubuntu/tp2-info.txt <<INFOEOF
=================================================================
TP2 - Odoo + Bucardo - Noeud SLAVE/REPLICA
=================================================================
Instance ID    : $$INSTANCE_ID
Availability Zone : $$AZ
Local IP       : $$LOCAL_IP
Peer (Master) IP : $$PEER_PRIVATE_IP
Role           : SLAVE (Bucardo gere depuis le master)

Acces Odoo:
  http://$$LOCAL_IP:8069

Note: Bucardo sera configure depuis le master.

Logs Odoo:
  cd /opt/odoo && docker compose logs -f odoo
=================================================================
INFOEOF

chmod 644 /home/ubuntu/tp2-info.txt
chown ubuntu:ubuntu /home/ubuntu/tp2-info.txt

echo "===== Installation SLAVE terminee! ====="
echo "Acces Odoo: http://$$LOCAL_IP:8069"
