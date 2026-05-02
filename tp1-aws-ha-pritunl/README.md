# TP1 — Architecture EC2 en Haute Disponibilité avec Pritunl VPN

Architecture AWS multi-AZ déployée avec Terraform, comprenant:

- **VPC multi-AZ** (Stockholm `eu-north-1`) avec subnets publics, privés et BDD isolés
- **Auto Scaling Group** d'instances EC2 derrière un **Application Load Balancer**
- **Pritunl VPN Server** installé automatiquement sur chaque instance via user_data
- **RDS MySQL Multi-AZ** dans des subnets privés isolés
- **S3 Bucket** chiffré avec versioning et lifecycle
- **Lambda function** déclenchée par les uploads S3, déployée dans le VPC
- **Auto Scaling policies** basées sur l'utilisation CPU
- **Security Groups** stricts entre les composants

## Architecture

```
Internet
    │
    ▼
┌────────────────────────────────────────────────────┐
│                ALB (HTTPS public)                  │
└─────────────────┬──────────────────────────────────┘
                  │
       ┌──────────┴──────────┐
       ▼                     ▼
   ┌───────┐             ┌───────┐
   │ AZ-1a │             │ AZ-1b │
   │       │             │       │
   │ ┌───┐ │             │ ┌───┐ │
   │ │EC2│ │   Pritunl   │ │EC2│ │
   │ │VPN│ │  + MongoDB  │ │VPN│ │
   │ └───┘ │             │ └───┘ │
   └───┬───┘             └───┬───┘
       │                     │
       └─────────┬───────────┘
                 ▼
       ┌─────────────────┐
       │  RDS MySQL HA   │
       │   (Multi-AZ)    │
       └─────────────────┘
                 │
       ┌─────────▼─────────┐
       │  Lambda + S3      │
       └───────────────────┘
```

## Prérequis

1. **Compte AWS** avec credentials configurés (`aws configure` ou variables d'env)
2. **Terraform** >= 1.5.0 ([installation](https://developer.hashicorp.com/terraform/install))
3. **AWS CLI** ([installation](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html))

## Déploiement

### 1. Configurer les variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Éditer terraform.tfvars et changer au minimum db_password
```

Tu peux aussi utiliser une variable d'environnement pour le mot de passe (plus secure):

```bash
export TF_VAR_db_password="MonMotDePasseUltra-Secure!"
```

### 2. Initialiser Terraform

```bash
terraform init
```

### 3. Vérifier le plan

```bash
terraform plan
```

### 4. Déployer

```bash
terraform apply
```

Le déploiement prend environ **15-20 minutes**:
- ~5 min pour le RDS Multi-AZ (le plus long)
- ~2 min pour l'ALB
- ~10 min pour les EC2 (l'install Pritunl + MongoDB prend du temps via user_data)

## Accès à Pritunl

### 1. Récupérer l'URL de l'ALB

```bash
terraform output alb_url
```

### 2. Accéder à l'interface

Ouvre l'URL dans ton navigateur. Tu auras un avertissement de certificat (self-signed) — accepte-le.

### 3. Récupérer la setup-key et le mot de passe

Tu as plusieurs options:

#### Option A — Via SSM Session Manager (recommandé, pas de SSH)

```bash
# Récupérer l'ID d'une instance
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:AutoScalingGroup,Values=$(terraform output -raw asg_name)" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text \
  --region eu-north-1)

# Se connecter via SSM
aws ssm start-session --target $INSTANCE_ID --region eu-north-1

# Une fois connecté:
sudo cat /home/ubuntu/pritunl-info.txt
# ou
sudo pritunl setup-key
sudo pritunl default-password
```

#### Option B — Via SSH (si key_pair configurée)

```bash
# Récupérer l'IP publique
aws ec2 describe-instances \
  --filters "Name=tag:AutoScalingGroup,Values=$(terraform output -raw asg_name)" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].PublicIpAddress' \
  --output text \
  --region eu-north-1

# SSH
ssh -i ta-key.pem ubuntu@<IP_PUBLIQUE>
cat /home/ubuntu/pritunl-info.txt
```

### 4. Configuration initiale

1. Sur la page de setup Pritunl, coller la **setup-key** + URL MongoDB (`mongodb://localhost:27017/pritunl`)
2. Se logger avec le **default password**
3. Changer le mot de passe
4. Créer une **organisation** et un **utilisateur**
5. Créer un **server** VPN (port UDP 1194 par défaut)
6. Attacher l'organisation au server et démarrer le server
7. Télécharger le profil utilisateur (`.tar`) et l'importer dans le client Pritunl

## Tester l'architecture

### Tester l'ALB

```bash
curl -k https://$(terraform output -raw alb_dns_name)
```

### Tester le S3 → Lambda

```bash
echo "test" > test.txt
aws s3 cp test.txt s3://$(terraform output -raw s3_bucket_name)/

# Vérifier les logs Lambda
aws logs tail /aws/lambda/$(terraform output -raw lambda_function_name) --follow --region eu-north-1
```

### Tester le RDS depuis une EC2

```bash
# Via SSM sur une instance
aws ssm start-session --target <INSTANCE_ID> --region eu-north-1

# Puis dans la session:
mysql -h <rds_address> -u admin -p
```

### Vérifier la HA — terminer une instance

```bash
# Lister les instances
aws ec2 describe-instances \
  --filters "Name=tag:AutoScalingGroup,Values=$(terraform output -raw asg_name)" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text \
  --region eu-north-1

# Terminer une instance — l'ASG en relancera une nouvelle
aws ec2 terminate-instances --instance-ids <INSTANCE_ID> --region eu-north-1
```

## Sécurité — points à durcir en prod

⚠️ Cette config est optimisée pour un TP. Pour un usage prod:

1. **`allowed_admin_cidr`** → mettre votre IP /32, pas `0.0.0.0/0`
2. **`db_password`** → utiliser AWS Secrets Manager
3. **Certificat ACM** → utiliser un certif validé via DNS sur un vrai domaine au lieu du self-signed
4. **NAT Gateway** → un par AZ pour éviter le SPOF
5. **`deletion_protection`** → activer sur RDS et ALB
6. **`skip_final_snapshot`** → mettre à `false` sur RDS
7. **MongoDB en cluster** → pour un vrai cluster Pritunl HA, déployer MongoDB sur une infra dédiée (DocumentDB ou EC2 dédiées) au lieu de localhost sur chaque EC2
8. **VPC Endpoints** → pour S3 et SSM, éviter de passer par Internet

## Limitations connues

### MongoDB en local sur chaque EC2

Pour ce TP, chaque EC2 a sa propre instance MongoDB locale. Cela signifie que **chaque Pritunl est indépendant** — ce n'est pas un vrai cluster avec données partagées. C'est acceptable pour un TP HA (l'ALB peut router vers n'importe quelle instance), mais pour un cluster Pritunl en prod il faut une BDD MongoDB partagée.

Pour un vrai cluster Pritunl, il faudrait:
- Soit déployer MongoDB sur des EC2 dédiées avec replica set
- Soit utiliser AWS DocumentDB (compatible MongoDB)
- Puis pointer tous les Pritunl vers ce backend MongoDB partagé

## Destruction

```bash
# IMPORTANT: vider le bucket S3 d'abord (sinon erreur)
aws s3 rm s3://$(terraform output -raw s3_bucket_name) --recursive

terraform destroy
```

## Coûts estimés

Pour un environnement de TP en `eu-north-1`, à titre indicatif et hors free tier:
- 2x t3.small EC2: ~30 USD/mois
- 1x db.t3.micro RDS Multi-AZ: ~30 USD/mois
- ALB: ~20 USD/mois
- NAT Gateway: ~35 USD/mois
- S3 + Lambda: négligeable
- **Total: ~115 USD/mois**

Pense à `terraform destroy` quand tu as fini! 💸

## Structure du projet

```
.
├── main.tf                      # Provider + AMI + locals
├── variables.tf                 # Variables paramétrables
├── vpc.tf                       # VPC, subnets, IGW, NAT, route tables
├── security_groups.tf           # SG ALB, EC2, RDS, Lambda
├── alb.tf                       # ALB + Target Group + Listeners + cert
├── ec2.tf                       # Launch Template + ASG + IAM + scaling
├── rds.tf                       # RDS MySQL Multi-AZ
├── s3.tf                        # Bucket S3 + lifecycle + notification
├── lambda.tf                    # Lambda + IAM + log group
├── outputs.tf                   # Outputs utiles
├── user_data.sh                 # Script install Pritunl + MongoDB
├── lambda_function.py           # Code Python Lambda
├── terraform.tfvars.example     # Exemple de config
└── README.md                    # Cette doc
```
