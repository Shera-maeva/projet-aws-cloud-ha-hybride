#!/bin/bash
###############################################################################
# Script d'installation Pritunl VPN + MongoDB sur Ubuntu 22.04
# Référence: https://docs.pritunl.com/docs/installation
###############################################################################

set -e
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "===== Démarrage de l'installation Pritunl ====="

# -----------------------------------------------------------------------------
# Mise à jour du système
# -----------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

# Outils utiles
apt-get install -y curl wget gnupg lsb-release ca-certificates apt-transport-https \
    awscli mysql-client unzip jq

# -----------------------------------------------------------------------------
# Ajout du dépôt Pritunl
# -----------------------------------------------------------------------------
echo "===== Ajout du dépôt Pritunl ====="
tee /etc/apt/sources.list.d/pritunl.list <<EOF
deb https://repo.pritunl.com/stable/apt jammy main
EOF

# Clé GPG Pritunl
curl -fsSL https://raw.githubusercontent.com/pritunl/pgp/master/pritunl_repo_pub.asc | \
    gpg --dearmor -o /usr/share/keyrings/pritunl.gpg
# Réécriture avec signed-by pour les versions modernes d'apt
tee /etc/apt/sources.list.d/pritunl.list <<EOF
deb [signed-by=/usr/share/keyrings/pritunl.gpg] https://repo.pritunl.com/stable/apt jammy main
EOF

# -----------------------------------------------------------------------------
# Ajout du dépôt MongoDB 6.0 (Pritunl est construit sur MongoDB)
# -----------------------------------------------------------------------------
echo "===== Ajout du dépôt MongoDB 6.0 ====="
curl -fsSL https://pgp.mongodb.com/server-6.0.asc | \
    gpg --dearmor -o /usr/share/keyrings/mongodb-server-6.0.gpg

tee /etc/apt/sources.list.d/mongodb-org-6.0.list <<EOF
deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse
EOF

# -----------------------------------------------------------------------------
# Installation de Pritunl + MongoDB + WireGuard
# -----------------------------------------------------------------------------
echo "===== Installation des paquets ====="
apt-get update -y
apt-get install -y pritunl mongodb-org wireguard wireguard-tools

# -----------------------------------------------------------------------------
# Configuration MongoDB
# -----------------------------------------------------------------------------
systemctl enable mongod
systemctl start mongod

# Attendre que MongoDB soit bien up
echo "===== Attente que MongoDB démarre ====="
for i in {1..30}; do
    if systemctl is-active --quiet mongod; then
        echo "MongoDB est opérationnel"
        break
    fi
    sleep 2
done

# -----------------------------------------------------------------------------
# Configuration Pritunl
# -----------------------------------------------------------------------------
echo "===== Configuration Pritunl ====="

# Désactivation de la transparent hugepage (recommandé par MongoDB/Pritunl)
cat > /etc/systemd/system/disable-transparent-huge-pages.service <<EOF
[Unit]
Description=Disable Transparent Huge Pages (THP)
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=mongod.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never | tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null'

[Install]
WantedBy=basic.target
EOF

systemctl daemon-reload
systemctl enable disable-transparent-huge-pages
systemctl start disable-transparent-huge-pages

# Démarrage et activation de Pritunl
systemctl enable pritunl
systemctl start pritunl

# Attendre que Pritunl démarre
echo "===== Attente que Pritunl démarre ====="
for i in {1..30}; do
    if systemctl is-active --quiet pritunl; then
        echo "Pritunl est opérationnel"
        break
    fi
    sleep 2
done

# -----------------------------------------------------------------------------
# Récupération des infos d'instance
# -----------------------------------------------------------------------------
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/instance-id)
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/public-ipv4 || echo "no-public-ip")
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/local-ipv4)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/placement/availability-zone)

# -----------------------------------------------------------------------------
# Génération de la setup-key et du mot de passe par défaut
# -----------------------------------------------------------------------------
sleep 10 # Attendre un peu plus pour s'assurer que pritunl a fini son init
SETUP_KEY=$(pritunl setup-key 2>/dev/null || echo "Pas encore disponible")
DEFAULT_PASSWORD=$(pritunl default-password 2>/dev/null || echo "Pas encore disponible")

# Création d'un fichier d'infos accessible via SSH
cat > /home/ubuntu/pritunl-info.txt <<EOF
=================================================================
PRITUNL VPN - Informations d'accès
=================================================================
Instance ID    : $INSTANCE_ID
Availability Zone : $AZ
Private IP     : $PRIVATE_IP
Public IP      : $PUBLIC_IP

Setup Key      : $SETUP_KEY

Default Login  :
$DEFAULT_PASSWORD

URL d'accès direct : https://$PUBLIC_IP
=================================================================

Pour récupérer ces infos plus tard:
  - Setup Key       : sudo pritunl setup-key
  - Default Password: sudo pritunl default-password
=================================================================
EOF

chmod 644 /home/ubuntu/pritunl-info.txt
chown ubuntu:ubuntu /home/ubuntu/pritunl-info.txt

# -----------------------------------------------------------------------------
# Tag CloudWatch / log final
# -----------------------------------------------------------------------------
echo "===== Installation terminée avec succès ====="
echo "Instance: $INSTANCE_ID dans $AZ"
echo "Pritunl est accessible sur https://$PUBLIC_IP"
echo "Setup Key: $SETUP_KEY"

# Activation de l'IP forwarding (nécessaire pour le VPN)
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

echo "===== Fin du user_data ====="
