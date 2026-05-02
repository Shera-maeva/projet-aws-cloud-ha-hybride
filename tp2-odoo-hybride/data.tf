###############################################################################
# Recuperation des ressources du TP1 (par tags)
# On lit l'infra existante sans la modifier
###############################################################################

# -----------------------------------------------------------------------------
# Recuperation du VPC du TP1 (par tag Name)
# -----------------------------------------------------------------------------
data "aws_vpc" "tp1" {
  tags = {
    Name = "${var.tp1_project_name}-${var.tp1_environment}-vpc"
  }
}

# -----------------------------------------------------------------------------
# Recuperation des subnets publics du TP1
# (on va y mettre les EC2 Odoo pour qu'elles soient accessibles)
# -----------------------------------------------------------------------------
data "aws_subnets" "tp1_public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.tp1.id]
  }

  tags = {
    Tier = "public"
  }
}

# -----------------------------------------------------------------------------
# Recuperation des Availability Zones disponibles
# -----------------------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available"
}

# -----------------------------------------------------------------------------
# Locals derives
# -----------------------------------------------------------------------------
locals {
  vpc_id            = data.aws_vpc.tp1.id
  public_subnet_ids = data.aws_subnets.tp1_public.ids
  azs               = slice(data.aws_availability_zones.available.names, 0, 2)
}
