###############################################################################
# TP1 - Architecture EC2 en Haute Disponibilité avec Pritunl VPN
# Provider AWS et configuration globale
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      TP          = "TP1-HA-Pritunl"
    }
  }
}

# Récupération des AZ disponibles dans la région
data "aws_availability_zones" "available" {
  state = "available"
}

# Récupération de la dernière AMI Ubuntu 22.04 LTS
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Suffixe aléatoire pour les ressources qui requièrent un nom unique (S3)
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # On utilise les 2 premières AZ de la région pour la HA
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  name_prefix = "${var.project_name}-${var.environment}"
}
