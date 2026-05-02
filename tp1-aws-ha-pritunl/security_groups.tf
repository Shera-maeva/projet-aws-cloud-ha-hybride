###############################################################################
# Security Groups
###############################################################################

# -----------------------------------------------------------------------------
# SG pour le Load Balancer (publiquement accessible en HTTP/HTTPS)
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Security group for the Application Load Balancer"
  vpc_id      = aws_vpc.main.id

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
# SG pour les EC2 (Pritunl VPN)
# Pritunl écoute sur:
#   - 80/443 pour l'interface admin web
#   - 1194/UDP (et autres) pour OpenVPN
#   - 51820/UDP pour WireGuard
# -----------------------------------------------------------------------------
resource "aws_security_group" "ec2" {
  name        = "${local.name_prefix}-ec2-sg"
  description = "Security group for the Pritunl EC2 instances"
  vpc_id      = aws_vpc.main.id

  # Trafic HTTP/HTTPS from ALB uniquement (pour l'interface Pritunl)
  ingress {
    description     = "HTTP depuis ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "HTTPS depuis ALB"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Direct admin access to Pritunl interface from allowed IP
  # Utile en debug pour accéder directement à l'instance sans passer par l'ALB
  ingress {
    description = "Admin Pritunl direct"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_admin_cidr]
  }

  # OpenVPN standard port
  ingress {
    description = "OpenVPN UDP"
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Additional OpenVPN port range used by Pritunl
  ingress {
    description = "Pritunl OpenVPN range UDP"
    from_port   = 10000
    to_port     = 19999
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # WireGuard
  ingress {
    description = "WireGuard UDP"
    from_port   = 51820
    to_port     = 51820
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH depuis IP autorisée (debug uniquement)
  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_admin_cidr]
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

# -----------------------------------------------------------------------------
# SG pour le RDS — accessible uniquement depuis les EC2 et Lambda
# -----------------------------------------------------------------------------
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "Security group for the RDS MySQL database"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  ingress {
    description     = "MySQL from Lambda"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-rds-sg"
  }
}

# -----------------------------------------------------------------------------
# SG pour la Lambda (qui sera dans le VPC pour accéder au RDS)
# -----------------------------------------------------------------------------
resource "aws_security_group" "lambda" {
  name        = "${local.name_prefix}-lambda-sg"
  description = "Security group for the Lambda function"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-lambda-sg"
  }
}
