# TP2 - Déploiement Applicatif Automatisé en HA

Déploiement automatisé d'**Odoo 19** en mode **Master-Master** avec réplication **Bucardo** sur l'infrastructure AWS du TP1, pour démontrer la **haute disponibilité applicative** dans un environnement **Cloud Hybride** sécurisé par le VPN Pritunl.

## 🎯 Objectif du TP

Le TP1 démontrait la **haute disponibilité d'infrastructure** (auto-recovery des EC2). Le TP2 va plus loin en ajoutant la **haute disponibilité applicative** : si une instance Odoo tombe en panne, l'utilisateur peut continuer son travail sur la seconde instance grâce à la **réplication multi-master des données** entre les bases PostgreSQL.

## 🏗️ Architecture déployée

```
                    INTERNET
                       │
                       ▼
               ┌──────────────┐
               │  ALB Odoo    │ (HTTP, port 80, sticky sessions)
               │  (TP2)       │
               └───────┬──────┘
                       │
            ┌──────────┴──────────┐
            ▼                     ▼
      ╔═══════════╗         ╔═══════════╗
      ║ AZ-1a     ║         ║ AZ-1b     ║
      ║           ║         ║           ║
      ║ EC2 Master║         ║ EC2 Slave ║
      ║           ║         ║           ║
      ║ Docker:   ║         ║ Docker:   ║
      ║  - Odoo19 ║         ║  - Odoo19 ║
      ║  - Postgres║◄═══════║  - Postgres║
      ║  - Bucardo║ multi-  ║           ║
      ║           ║  master ║           ║
      ╚═══════════╝         ╚═══════════╝
            │                     │
            └─────────┬───────────┘
                      ▼
              VPC du TP1 (réutilisé)
              + VPN Pritunl du TP1
                  (Cloud Hybride)
```

## 📋 Prérequis

1. **TP1 déployé et fonctionnel** sur AWS (le VPC `tp1-ha-dev-vpc` doit exister)
2. **Terraform** ≥ 1.5.0
3. **AWS CLI** configuré (`aws configure`)
4. **Plugin SSM** (déjà installé pour le TP1)

## 🚀 Déploiement (étapes)

### 1️⃣ Configuration

```cmd
cd C:\tp2-odoo-hybride
copy terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars
```

⚠️ **Change absolument les 3 mots de passe** dans le fichier (postgres, odoo_admin, bucardo).

### 2️⃣ Initialisation et déploiement

```cmd
terraform init
terraform plan
terraform apply
```

Tape `yes` quand demandé. Le déploiement prend **8-12 minutes** :
- ~2 min pour les ressources AWS
- ~6-10 min pour l'install Docker + Pull Odoo + Pull Postgres + Bucardo

### 3️⃣ Récupérer les infos

```cmd
terraform output
```

Tu auras :
- `alb_url` : URL d'accès via le LB
- `odoo_master_url_direct` : URL directe Master
- `odoo_slave_url_direct` : URL directe Slave
- `odoo_master_instance_id` / `odoo_slave_instance_id` : pour les commandes AWS

## 🛠️ Configuration post-déploiement

### Étape A — Initialisation Odoo (sur les 2 nœuds)

⚠️ **Important** : il faut initialiser Odoo sur **les 2 nœuds** avant de lancer Bucardo, sinon les schémas seront différents.

#### Sur le Master :
1. Va sur `http://<IP_MASTER>:8069`
2. Tu arrives sur la page de création de BDD
3. Remplis :
   - Master Password : `AdminOdoo2026` (ou ce que tu as défini)
   - Database Name : `odoo`
   - Email : `admin@tp2.local`
   - Password : choisis-en un (ex: `OdooAdmin123`)
   - Language : Français
   - Country : ton choix
   - **DÉCOCHE "Demo data"** (important pour limiter les conflits Bucardo)
4. Clique **Create database**
5. Attends 1-2 minutes que la BDD soit créée

#### Sur le Slave :
1. Va sur `http://<IP_SLAVE>:8069`
2. **Pareille** procédure, **avec exactement les mêmes paramètres** :
   - Database Name : `odoo` (même nom!)
   - Email : `admin@tp2.local` (même email!)
   - Password : **le même** que sur le Master
3. Clique **Create database**

### Étape B — Configuration Bucardo (sur le Master)

Une fois les 2 BDD initialisées :

```cmd
aws ssm start-session --target <ODOO_MASTER_INSTANCE_ID> --region eu-north-1
```

Dans la session SSM :

```bash
cd /opt/odoo
sudo ./setup-bucardo.sh <SLAVE_PRIVATE_IP>
```

Bucardo va :
1. Créer les utilisateurs `bucardo` sur les 2 BDD
2. Installer l'extension `plperl`
3. Ajouter toutes les tables Odoo au pool de réplication
4. Démarrer la synchronisation multi-master

### Étape C — Vérification Bucardo

```bash
sudo bucardo status
sudo bucardo list syncs
sudo bucardo list dbs
```

Tu devrais voir le sync `odoo_sync` en état **Good**.

## 🧪 Tests à effectuer

### Test 1 — Réplication des données

1. Va sur le **Master** : `http://<IP_MASTER>:8069`
2. Ouvre **Sales** → crée un nouveau client (ex: "Client Test 1")
3. Va sur le **Slave** : `http://<IP_SLAVE>:8069`
4. Ouvre **Sales** → tu dois voir "Client Test 1" ✅
5. Sur le **Slave**, crée "Client Test 2"
6. Retourne sur le **Master** → "Client Test 2" doit apparaître ✅

→ **C'est la preuve de la réplication multi-master !**

### Test 2 — Failover applicatif (LA démo HA)

1. Connecte-toi à Odoo via l'ALB : `http://<ALB_DNS>`
2. Tu seras automatiquement routée sur un des 2 nœuds (Master ou Slave)
3. Note où tu es (regarde la barre de statut)
4. Crée un client "Client Avant Crash"
5. **Tue le nœud où tu es** :
   ```cmd
   aws ec2 stop-instances --instance-ids <INSTANCE_ID> --region eu-north-1
   ```
6. Attends 60 secondes
7. Rafraîchis la page Odoo (F5)
8. → L'ALB te route vers l'autre nœud
9. → "Client Avant Crash" est **toujours là** ✅

→ **C'est la HA applicative complète !**

## 🌐 Cloud Hybride (rappel TP1)

Pour démontrer le caractère hybride :
1. Connecte-toi au VPN Pritunl du TP1 (client Pritunl)
2. Une fois connectée au VPN, tu peux accéder à Odoo via les **IPs privées** :
   - `http://10.0.1.50:8069` (Master)
   - `http://10.0.2.50:8069` (Slave)
3. Cela prouve que ton "réseau local" (ton PC) est connecté à l'AWS via le VPN

## 🚨 Limitations connues

Le mode multi-master Odoo+Bucardo a des limites bien documentées :

1. **Conflits de séquences PostgreSQL** : si les 2 nœuds créent un enregistrement en même temps, possible conflit de clé primaire
2. **DDL non répliqué** : si tu installes un module Odoo, il faut le faire sur les 2 nœuds
3. **Pas de transactions atomiques distribuées** : la cohérence est éventuelle (asynchrone)

**Mitigation** : pour la démo, faire les actions sur **un seul nœud à la fois** et attendre la réplication.

## 🧹 Destruction

```cmd
terraform destroy
```

⚠️ **Note** : le destroy du TP2 ne touche **pas** au TP1 (VPC, EC2 Pritunl, etc.). 

## 📂 Structure des fichiers

```
tp2-odoo-hybride/
├── main.tf                      # Provider + AMI
├── variables.tf                 # Variables paramétrables
├── data.tf                      # Lecture du VPC TP1
├── ec2_odoo.tf                  # 2 EC2 Odoo + EIP + IAM
├── alb_odoo.tf                  # ALB + Target Group + Listener
├── security_groups.tf           # SG ALB + SG EC2 (descriptions sans accents!)
├── outputs.tf                   # Outputs utiles
├── user_data_odoo_master.sh     # Script install Master + Bucardo
├── user_data_odoo_slave.sh      # Script install Slave
├── terraform.tfvars.example     # Exemple de config
└── README.md                    # Cette doc
```

## 🎓 Ce que ce TP démontre

| Concept | Comment |
|---|---|
| **Conteneurisation** | Docker + docker-compose pour Odoo et Postgres |
| **HA applicative** | Bucardo replique les données entre 2 BDD |
| **Master-Master** | Les 2 nœuds peuvent recevoir des écritures |
| **Cloud Hybride** | VPN Pritunl du TP1 relie le "local" au cloud |
| **IaC** | Tout le déploiement automatisé via Terraform |
| **Failover** | L'ALB route vers le nœud sain si l'autre tombe |

## 💸 Coûts estimés

- 2x EC2 t3.medium : ~$60/mois
- 1x ALB : ~$20/mois
- 2x EIP : ~$7/mois
- **Total TP2 : ~$87/mois**
- **Total TP1+TP2 : ~$200/mois**

⚠️ **Pense à `terraform destroy` après la présentation !**
