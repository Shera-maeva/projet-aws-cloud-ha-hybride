###############################################################################
# Variables du projet
###############################################################################

variable "aws_region" {
  description = "Région AWS pour le déploiement"
  type        = string
  default     = "eu-north-1" # Stockholm
}

variable "project_name" {
  description = "Nom du projet (utilisé comme préfixe pour les ressources)"
  type        = string
  default     = "tp1-ha"
}

variable "environment" {
  description = "Nom de l'environnement"
  type        = string
  default     = "dev"
}

# -----------------------------------------------------------------------------
# Réseau
# -----------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR du VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs des subnets publics (un par AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs des subnets privés pour les EC2"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "db_subnet_cidrs" {
  description = "CIDRs des subnets dédiés à la BDD"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

variable "allowed_admin_cidr" {
  description = "CIDR autorisé pour l'accès admin SSH/HTTPS Pritunl. METTRE TON IP /32 EN PROD!"
  type        = string
  default     = "0.0.0.0/0"
}

# -----------------------------------------------------------------------------
# EC2 / Auto Scaling
# -----------------------------------------------------------------------------
variable "instance_type" {
  description = "Type d'instance EC2"
  type        = string
  default     = "t3.small" # Pritunl + MongoDB ont besoin d'au moins 2GB RAM
}

variable "asg_min_size" {
  description = "Nombre minimum d'instances dans l'ASG"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Nombre maximum d'instances dans l'ASG"
  type        = number
  default     = 4
}

variable "asg_desired_capacity" {
  description = "Nombre désiré d'instances"
  type        = number
  default     = 2
}

variable "key_pair_name" {
  description = "Nom de la key pair EC2 pour SSH (laisser vide si pas besoin de SSH)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# RDS
# -----------------------------------------------------------------------------
variable "db_instance_class" {
  description = "Classe d'instance RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Nom de la base de données initiale"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Utilisateur master RDS"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "Mot de passe master RDS (utiliser TF_VAR_db_password en variable d'env)"
  type        = string
  sensitive   = true
  # Pas de default — à fournir via terraform.tfvars ou variable d'environnement
}

variable "db_allocated_storage" {
  description = "Stockage en GB pour le RDS"
  type        = number
  default     = 20
}
