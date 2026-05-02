###############################################################################
# Variables du projet TP2
###############################################################################

variable "aws_region" {
  description = "Region AWS pour le deploiement"
  type        = string
  default     = "eu-north-1" # Stockholm, meme region que le TP1
}

variable "project_name" {
  description = "Nom du projet"
  type        = string
  default     = "tp2-odoo"
}

variable "environment" {
  description = "Environnement"
  type        = string
  default     = "dev"
}

# -----------------------------------------------------------------------------
# Reference au TP1 (par tags pour retrouver le VPC)
# -----------------------------------------------------------------------------
variable "tp1_project_name" {
  description = "Nom du projet TP1 (pour retrouver son VPC)"
  type        = string
  default     = "tp1-ha"
}

variable "tp1_environment" {
  description = "Environnement du TP1"
  type        = string
  default     = "dev"
}

# -----------------------------------------------------------------------------
# Configuration EC2 Odoo
# -----------------------------------------------------------------------------
variable "instance_type" {
  description = "Type d'instance pour les EC2 Odoo"
  type        = string
  # Odoo + Postgres + Bucardo : besoin de RAM
  default     = "t3.medium" # 2 vCPU, 4 Go RAM
}

variable "key_pair_name" {
  description = "Nom de la key pair EC2 (optionnel)"
  type        = string
  default     = ""
}

variable "allowed_admin_cidr" {
  description = "CIDR autorise pour SSH/admin (utiliser ton IP en prod)"
  type        = string
  default     = "0.0.0.0/0"
}

# -----------------------------------------------------------------------------
# Configuration Odoo / PostgreSQL
# -----------------------------------------------------------------------------
variable "odoo_version" {
  description = "Version d'Odoo a deployer"
  type        = string
  default     = "19" # Odoo 19 comme demande dans le TP
}

variable "postgres_version" {
  description = "Version de PostgreSQL"
  type        = string
  default     = "15"
}

variable "postgres_password" {
  description = "PostgreSQL password (set in terraform.tfvars)"
  type        = string
  sensitive   = true
}

variable "odoo_admin_password" {
  description = "Odoo admin password (set in terraform.tfvars)"
  type        = string
  sensitive   = true
}

variable "bucardo_password" {
  description = "Bucardo replication password (set in terraform.tfvars)"
  type        = string
  sensitive   = true
}