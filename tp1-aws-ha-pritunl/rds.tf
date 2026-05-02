###############################################################################
# RDS MySQL Multi-AZ
###############################################################################

# -----------------------------------------------------------------------------
# Subnet group pour le RDS (utilise les subnets DB isolés)
# -----------------------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = aws_subnet.db[*].id

  tags = {
    Name = "${local.name_prefix}-db-subnet-group"
  }
}

# -----------------------------------------------------------------------------
# Parameter group MySQL 8.0
# -----------------------------------------------------------------------------
resource "aws_db_parameter_group" "mysql" {
  name   = "${local.name_prefix}-mysql-params"
  family = "mysql8.0"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = {
    Name = "${local.name_prefix}-mysql-params"
  }
}

# -----------------------------------------------------------------------------
# Instance RDS MySQL Multi-AZ
# -----------------------------------------------------------------------------
resource "aws_db_instance" "main" {
  identifier     = "${local.name_prefix}-mysql"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 3306

  # ----- HAUTE DISPONIBILITÉ -----
  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.mysql.name

  # Backups
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # Pour le TP — en prod mettre à false
  skip_final_snapshot       = true
  final_snapshot_identifier = null
  deletion_protection       = false
  apply_immediately         = true

  # Pas d'accès public (subnets BDD isolés)
  publicly_accessible = false

  performance_insights_enabled = false # à activer en prod
  monitoring_interval          = 0     # 60 en prod pour les enhanced metrics

  tags = {
    Name = "${local.name_prefix}-mysql"
  }
}
