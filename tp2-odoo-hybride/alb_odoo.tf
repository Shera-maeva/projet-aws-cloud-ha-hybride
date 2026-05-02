###############################################################################
# Application Load Balancer pour Odoo
# IMPORTANT: HTTP only (pas de HTTPS pour eviter le souci ACM self-signed du TP1)
###############################################################################

# -----------------------------------------------------------------------------
# ALB
# -----------------------------------------------------------------------------
resource "aws_lb" "odoo" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_odoo.id]
  subnets            = local.public_subnet_ids

  enable_deletion_protection = false

  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

# -----------------------------------------------------------------------------
# Target Group pour Odoo (port 8069)
# IMPORTANT: stickiness active des le depart (lecon TP1)
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "odoo" {
  name     = "${local.name_prefix}-tg"
  port     = 8069
  protocol = "HTTP"
  vpc_id   = local.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/web/login"
    protocol            = "HTTP"
    port                = "8069"
    matcher             = "200-399"
  }

  # Sticky sessions ACTIVES des le depart pour eviter les boucles de login
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = true
  }

  tags = {
    Name = "${local.name_prefix}-tg"
  }
}

# -----------------------------------------------------------------------------
# Attachement des 2 EC2 Odoo au target group
# -----------------------------------------------------------------------------
resource "aws_lb_target_group_attachment" "odoo_master" {
  target_group_arn = aws_lb_target_group.odoo.arn
  target_id        = aws_instance.odoo_master.id
  port             = 8069
}

resource "aws_lb_target_group_attachment" "odoo_slave" {
  target_group_arn = aws_lb_target_group.odoo.arn
  target_id        = aws_instance.odoo_slave.id
  port             = 8069
}

# -----------------------------------------------------------------------------
# Listener HTTP simple (pas de HTTPS pour eviter le souci ACM du TP1)
# -----------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.odoo.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.odoo.arn
  }
}
