# Projet AWS Cloud HA + Hybride

Projet réalisé dans le cadre du cours **Services Cloud AWS**.

## Structure du projet

Ce repository contient deux travaux pratiques liés:

### TP1 - Architecture AWS Haute Disponibilité avec Pritunl VPN
Dossier: `tp1-aws-ha-pritunl/`

Déploiement Terraform d'une infrastructure haute disponibilité multi-AZ sur AWS:
- VPC multi-AZ avec subnets publics, privés et BDD
- Auto Scaling Group de 2 EC2 Pritunl (VPN)
- Application Load Balancer
- RDS MySQL en mode Multi-AZ
- S3 chiffré KMS + Lambda Python

### TP2 - Odoo Master-Master via Bucardo en Cloud Hybride
Dossier: `tp2-odoo-hybride/`

Déploiement applicatif sur l'infrastructure du TP1:
- 2 EC2 t3.medium dédiées Odoo dans 2 AZ
- Docker: Odoo 19 + PostgreSQL 15
- Réplication multi-master via Bucardo 5.6
- Accessible depuis le réseau local via le VPN Pritunl du TP1

## Architecture globale

L'architecture combine:
- **TP1**: Haute disponibilité d'INFRASTRUCTURE (auto-recovery EC2, multi-AZ, load balancing)
- **TP2**: Haute disponibilité APPLICATIVE (réplication BDD multi-master)
- **Cloud Hybride**: Le VPN Pritunl du TP1 permet l'accès depuis le réseau local aux services du TP2

## Région AWS

eu-north-1 (Stockholm)

## Stack technologique

- Terraform 1.5+ (Infrastructure as Code)
- Ubuntu 22.04 LTS
- Pritunl + OpenVPN
- Docker + Docker Compose
- Odoo 19
- PostgreSQL 15
- Bucardo 5.6
- AWS: VPC, EC2, ALB, RDS, S3, Lambda, KMS, Auto Scaling

## Déploiement

Voir les README spécifiques dans chaque dossier:
- [tp1-aws-ha-pritunl/README.md](tp1-aws-ha-pritunl/README.md)
- [tp2-odoo-hybride/README.md](tp2-odoo-hybride/README.md)

## Sécurité

Les fichiers `terraform.tfvars` contenant les credentials sont volontairement exclus du repository.
Un fichier `terraform.tfvars.example` est fourni en template dans chaque dossier.

## Auteur

Shera-maeva
