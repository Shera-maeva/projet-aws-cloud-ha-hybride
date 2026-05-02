#!/bin/bash
###############################################################################
# Script user_data pour EC2 Odoo - Noeud MASTER (avec Bucardo)
# Installe Docker, Odoo 19, PostgreSQL et Bucardo pour replication multi-master
#
# IMPORTANT: tous les $ du bash sont echappes en $$ pour Terraform templatefile
###############################################################################

set -e
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "===== Demarrage de l installation Odoo MASTER ====="

# -----------------------------------------------------------------------------
# Variables (injectees par Terraform via templatefile - format $${VAR})
# -----------------------------------------------------------------------------
NODE_NAME="${node_name}"
NODE_ROLE="master"
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

echo "Local IP: $$LOCAL_IP, Peer IP: $$PEER_PRIVATE_IP, AZ: $$AZ"

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

# Configuration PostgreSQL pour replication
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

# docker-compose
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
echo "===== Attente PostgreSQL ====="
for i in {1..60}; do
    if docker exec odoo-db pg_isready -U odoo > /dev/null 2>&1; then
        echo "PostgreSQL pret!"
        break
    fi
    sleep 5
done

# Attente Odoo
echo "===== Attente Odoo ====="
for i in {1..60}; do
    if curl -s http://localhost:8069 > /dev/null 2>&1; then
        echo "Odoo pret!"
        break
    fi
    sleep 5
done

# Creation BDD odoo
echo "===== Creation BDD odoo ====="
sleep 30
docker exec odoo-db psql -U odoo -d postgres -c "CREATE DATABASE odoo OWNER odoo;" || true

# -----------------------------------------------------------------------------
# Installation Bucardo
# -----------------------------------------------------------------------------
echo "===== Installation de Bucardo ====="
apt-get install -y \
    bucardo \
    libdbi-perl \
    libdbd-pg-perl \
    libdbix-safe-perl \
    libboolean-perl \
    libencode-locale-perl || true

# Si bucardo pas dispo dans apt, install depuis git
if ! command -v bucardo &> /dev/null; then
    echo "===== Installation Bucardo depuis sources ====="
    apt-get install -y git make gcc \
        libdbi-perl libdbd-pg-perl libdbix-safe-perl libboolean-perl \
        libencode-locale-perl libpod-parser-perl
    
    cd /tmp
    git clone https://github.com/bucardo/bucardo.git
    cd bucardo
    perl Makefile.PL
    make
    make install
fi

mkdir -p /var/run/bucardo /var/log/bucardo
touch /var/log/bucardo/log.bucardo
chmod 777 /var/run/bucardo /var/log/bucardo

# -----------------------------------------------------------------------------
# Script de configuration Bucardo (a executer manuellement apres init Odoo)
# Note: ce script est en heredoc 'BUCARDOEOF' pour que les $ ne soient pas
# interpretes par bash a l'ecriture
# -----------------------------------------------------------------------------
cat > /opt/odoo/setup-bucardo.sh <<'BUCARDOEOF'
#!/bin/bash
set -e

PEER_IP="$1"
if [ -z "$PEER_IP" ]; then
    echo "Usage: $0 <peer_private_ip>"
    exit 1
fi

LOCAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
POSTGRES_PASSWORD="REPLACE_POSTGRES_PASSWORD"
BUCARDO_PASSWORD="REPLACE_BUCARDO_PASSWORD"

echo "===== Configuration de Bucardo ====="
echo "Local: $LOCAL_IP, Peer: $PEER_IP"

# Test connectivite locale
echo "Test connectivite locale..."
PGPASSWORD=$POSTGRES_PASSWORD psql -h $LOCAL_IP -U odoo -d odoo -c "SELECT version();" || { echo "Echec connexion locale"; exit 1; }

# Test connectivite peer
echo "Test connectivite peer..."
for i in {1..30}; do
    if PGPASSWORD=$POSTGRES_PASSWORD psql -h $PEER_IP -U odoo -d odoo -c "SELECT 1;" > /dev/null 2>&1; then
        echo "Peer accessible!"
        break
    fi
    echo "Attente du peer ($i/30)..."
    sleep 10
done

# User bucardo + extension plperl sur le master
echo "Configuration bucardo user sur le master..."
docker exec odoo-db psql -U odoo -d postgres -c "CREATE USER bucardo WITH SUPERUSER PASSWORD '$BUCARDO_PASSWORD';" || true
docker exec odoo-db psql -U odoo -d postgres -c "CREATE DATABASE bucardo OWNER bucardo;" || true
docker exec odoo-db psql -U bucardo -d odoo -c "CREATE EXTENSION IF NOT EXISTS plperl;" || true

# Configuration .bucardorc
cat > /root/.bucardorc <<RCEOF
dbhost=$LOCAL_IP
dbport=5432
dbname=bucardo
dbuser=bucardo
dbpass=$BUCARDO_PASSWORD
RCEOF

# Init Bucardo
echo "Initialisation Bucardo..."
bucardo install --batch --quiet --dbhost=$LOCAL_IP --dbport=5432 \
    --dbuser=bucardo --dbpass=$BUCARDO_PASSWORD || true

# Ajout BDD
echo "Ajout des BDD..."
bucardo add db db_master \
    dbhost=$LOCAL_IP dbport=5432 dbname=odoo dbuser=bucardo dbpass=$BUCARDO_PASSWORD

bucardo add db db_replica \
    dbhost=$PEER_IP dbport=5432 dbname=odoo dbuser=bucardo dbpass=$BUCARDO_PASSWORD

# Configuration peer
echo "Configuration bucardo user sur le peer..."
PGPASSWORD=$POSTGRES_PASSWORD psql -h $PEER_IP -U odoo -d postgres -c "CREATE USER bucardo WITH SUPERUSER PASSWORD '$BUCARDO_PASSWORD';" || true
PGPASSWORD=$BUCARDO_PASSWORD psql -h $PEER_IP -U bucardo -d odoo -c "CREATE EXTENSION IF NOT EXISTS plperl;" || true

# Ajout tables/sequences
echo "Ajout des tables..."
bucardo add all tables --herd=odoo_herd db=db_master || true
bucardo add all sequences db=db_master || true

# Creation sync multi-master
echo "Creation du sync..."
bucardo add sync odoo_sync \
    relgroup=odoo_herd \
    dbs=db_master:source,db_replica:source \
    autokick=1 || true

# Demarrage Bucardo
echo "Demarrage Bucardo..."
bucardo start

echo "===== Bucardo configure! ====="
echo "Pour voir le statut: sudo bucardo status"
BUCARDOEOF

# Substitution des passwords dans le script Bucardo
sed -i "s|REPLACE_POSTGRES_PASSWORD|$$POSTGRES_PASSWORD|g" /opt/odoo/setup-bucardo.sh
sed -i "s|REPLACE_BUCARDO_PASSWORD|$$BUCARDO_PASSWORD|g" /opt/odoo/setup-bucardo.sh
chmod +x /opt/odoo/setup-bucardo.sh

# -----------------------------------------------------------------------------
# Fichier d info pour l utilisateur
# -----------------------------------------------------------------------------
cat > /home/ubuntu/tp2-info.txt <<INFOEOF
=================================================================
TP2 - Odoo + Bucardo - Noeud MASTER
=================================================================
Instance ID    : $$INSTANCE_ID
Availability Zone : $$AZ
Local IP       : $$LOCAL_IP
Peer IP        : $$PEER_PRIVATE_IP
Role           : MASTER (Bucardo installe ici)

Acces Odoo:
  http://$$LOCAL_IP:8069
  Master Password (Initial Setup): $$ODOO_ADMIN_PASSWORD

Configuration Bucardo:
  Apres init Odoo sur les 2 noeuds, executer:
  cd /opt/odoo && sudo ./setup-bucardo.sh $$PEER_PRIVATE_IP

Logs Odoo:
  cd /opt/odoo && docker compose logs -f odoo

Status Bucardo:
  sudo bucardo status
=================================================================
INFOEOF

chmod 644 /home/ubuntu/tp2-info.txt
chown ubuntu:ubuntu /home/ubuntu/tp2-info.txt

echo "===== Installation MASTER terminee! ====="
echo "Acces Odoo: http://$$LOCAL_IP:8069"
