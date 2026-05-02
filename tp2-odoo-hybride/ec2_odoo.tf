###############################################################################
# 2 EC2 Odoo (1 Master Bucardo + 1 Replica)
# IPs Elastiques pour avoir des IPs stables (necessaire pour Bucardo)
###############################################################################

# -----------------------------------------------------------------------------
# IAM role pour les EC2 (acces SSM Session Manager + CloudWatch)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ec2_odoo" {
  name = "${local.name_prefix}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${local.name_prefix}-ec2-role"
  }
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_odoo.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_cw" {
  role       = aws_iam_role.ec2_odoo.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2_odoo" {
  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2_odoo.name
}

# -----------------------------------------------------------------------------
# IPs Elastiques (pour avoir des IPs publiques stables)
# Note: les IPs PRIVEES sont stables car on les fixe via private_ip
# -----------------------------------------------------------------------------
resource "aws_eip" "odoo_master" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-master-eip"
  }
}

resource "aws_eip" "odoo_slave" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-slave-eip"
  }
}

# -----------------------------------------------------------------------------
# Recuperation des CIDRs des subnets pour calculer les IPs privees fixes
# -----------------------------------------------------------------------------
data "aws_subnet" "public_az_a" {
  id = local.public_subnet_ids[0]
}

data "aws_subnet" "public_az_b" {
  id = local.public_subnet_ids[1]
}

# -----------------------------------------------------------------------------
# IPs privees fixes (calculees a partir du CIDR du subnet)
# Subnet 0 (AZ a) : par exemple 10.0.1.0/24 -> on prend .50
# Subnet 1 (AZ b) : par exemple 10.0.2.0/24 -> on prend .50
# -----------------------------------------------------------------------------
locals {
  master_private_ip = cidrhost(data.aws_subnet.public_az_a.cidr_block, 50)
  slave_private_ip  = cidrhost(data.aws_subnet.public_az_b.cidr_block, 50)
}

# -----------------------------------------------------------------------------
# EC2 MASTER (avec Bucardo, dans AZ a)
# -----------------------------------------------------------------------------
resource "aws_instance" "odoo_master" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = local.public_subnet_ids[0]
  private_ip    = local.master_private_ip

  vpc_security_group_ids = [aws_security_group.ec2_odoo.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_odoo.name
  key_name               = var.key_pair_name != "" ? var.key_pair_name : null

  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user_data_odoo_master.sh", {
    node_name           = "${local.name_prefix}-master"
    peer_private_ip     = local.slave_private_ip
    odoo_version        = var.odoo_version
    postgres_version    = var.postgres_version
    postgres_password   = var.postgres_password
    odoo_admin_password = var.odoo_admin_password
    bucardo_password    = var.bucardo_password
  })

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tags = {
    Name = "${local.name_prefix}-master"
    Role = "odoo-master-bucardo"
  }
}

# -----------------------------------------------------------------------------
# EC2 SLAVE/REPLICA (dans AZ b)
# -----------------------------------------------------------------------------
resource "aws_instance" "odoo_slave" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = local.public_subnet_ids[1]
  private_ip    = local.slave_private_ip

  vpc_security_group_ids = [aws_security_group.ec2_odoo.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_odoo.name
  key_name               = var.key_pair_name != "" ? var.key_pair_name : null

  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user_data_odoo_slave.sh", {
    node_name           = "${local.name_prefix}-slave"
    peer_private_ip     = local.master_private_ip
    odoo_version        = var.odoo_version
    postgres_version    = var.postgres_version
    postgres_password   = var.postgres_password
    odoo_admin_password = var.odoo_admin_password
    bucardo_password    = var.bucardo_password
  })

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tags = {
    Name = "${local.name_prefix}-slave"
    Role = "odoo-slave-replica"
  }
}

# -----------------------------------------------------------------------------
# Association des EIP aux instances
# -----------------------------------------------------------------------------
resource "aws_eip_association" "master" {
  instance_id   = aws_instance.odoo_master.id
  allocation_id = aws_eip.odoo_master.id
}

resource "aws_eip_association" "slave" {
  instance_id   = aws_instance.odoo_slave.id
  allocation_id = aws_eip.odoo_slave.id
}
