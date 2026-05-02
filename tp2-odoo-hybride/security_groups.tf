###############################################################################
# Security Groups pour l'infrastructure Odoo
# IMPORTANT: descriptions en anglais sans accents ni apostrophes (lecon TP1)
###############################################################################

# -----------------------------------------------------------------------------
# SG pour l'ALB Odoo (acces public HTTP)
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb_odoo" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Security group for Odoo Application Load Balancer"
  vpc_id      = local.vpc_id

  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-alb-sg"
  }
}

# -----------------------------------------------------------------------------
# SG pour les EC2 Odoo (port 8069 depuis ALB, port Postgres 5432 entre EC2)
# -----------------------------------------------------------------------------
resource "aws_security_group" "ec2_odoo" {
  name        = "${local.name_prefix}-ec2-sg"
  description = "Security group for Odoo EC2 instances"
  vpc_id      = local.vpc_id

  # Odoo web port from ALB
  ingress {
    description     = "Odoo web port from ALB"
    from_port       = 8069
    to_port         = 8069
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_odoo.id]
  }

  # Odoo longpolling port from ALB
  ingress {
    description     = "Odoo longpolling port from ALB"
    from_port       = 8072
    to_port         = 8072
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_odoo.id]
  }

  # Acces direct Odoo depuis admin (pour debug)
  ingress {
    description = "Odoo direct access for admin"
    from_port   = 8069
    to_port     = 8069
    protocol    = "tcp"
    cidr_blocks = [var.allowed_admin_cidr]
  }

  # PostgreSQL entre les EC2 Odoo (pour replication Bucardo)
  ingress {
    description = "PostgreSQL between Odoo EC2 instances for replication"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    self        = true
  }

  # SSH pour debug
  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_admin_cidr]
  }

  # ICMP pour ping (utile pour debug)
  ingress {
    description = "ICMP within VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [data.aws_vpc.tp1.cidr_block]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-ec2-sg"
  }
}
