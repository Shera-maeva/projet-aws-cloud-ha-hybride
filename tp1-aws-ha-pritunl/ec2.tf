###############################################################################
# Auto Scaling Group avec Launch Template
# Important: Pritunl a besoin d'IPs publiques pour servir les clients VPN,
# donc on déploie les EC2 dans les subnets PUBLICS (pas privés).
###############################################################################

# -----------------------------------------------------------------------------
# IAM Role pour les EC2 (accès S3, CloudWatch)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ec2" {
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

# Permission de lire/écrire dans le bucket S3 du projet
resource "aws_iam_role_policy" "ec2_s3" {
  name = "${local.name_prefix}-ec2-s3-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.app.arn,
          "${aws_s3_bucket.app.arn}/*"
        ]
      }
    ]
  })
}

# CloudWatch logs + SSM
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_cw" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# -----------------------------------------------------------------------------
# Launch Template
# -----------------------------------------------------------------------------
resource "aws_launch_template" "pritunl" {
  name_prefix   = "${local.name_prefix}-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  # Si une key_pair est fournie, on l'attache (utile pour le debug SSH)
  key_name = var.key_pair_name != "" ? var.key_pair_name : null

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  vpc_security_group_ids = [aws_security_group.ec2.id]

  # User data encodé en base64 pour installer Pritunl
  user_data = base64encode(file("${path.module}/user_data.sh"))

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 obligatoire
    http_put_response_hop_limit = 2
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.name_prefix}-pritunl"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${local.name_prefix}-pritunl-volume"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Auto Scaling Group multi-AZ
# -----------------------------------------------------------------------------
resource "aws_autoscaling_group" "pritunl" {
  name                = "${local.name_prefix}-asg"
  desired_capacity    = var.asg_desired_capacity
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  health_check_type   = "EC2" # On utilise EC2 (pas ELB) car Pritunl peut être lent à démarrer
  health_check_grace_period = 600 # 10 min — l'install Pritunl prend du temps

  # Déploiement dans les subnets PUBLICS pour Pritunl (besoin d'IP publique)
  vpc_zone_identifier = aws_subnet.public[*].id

  target_group_arns = [aws_lb_target_group.pritunl.arn]

  launch_template {
    id      = aws_launch_template.pritunl.id
    version = "$Latest"
  }

  # Stratégie de mise à jour: rolling update
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-pritunl-asg"
    propagate_at_launch = false
  }

  tag {
    key                 = "AutoScalingGroup"
    value               = "${local.name_prefix}-asg"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Politiques de scaling (optionnel mais bon pour le TP)
# -----------------------------------------------------------------------------
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${local.name_prefix}-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.pritunl.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${local.name_prefix}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.pritunl.name
}

# Alarme CloudWatch — scale up si CPU > 70%
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${local.name_prefix}-cpu-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Scale up si CPU >= 70%"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.pritunl.name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${local.name_prefix}-cpu-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 20
  alarm_description   = "Scale down si CPU <= 20%"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.pritunl.name
  }
}
