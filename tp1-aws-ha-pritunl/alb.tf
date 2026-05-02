###############################################################################
# Application Load Balancer (HTTP only pour le TP)
# Note: Pour HTTPS en prod, utiliser un cert ACM avec un vrai domaine validé
###############################################################################

resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

# -----------------------------------------------------------------------------
# Target Group - HTTP vers les EC2 Pritunl
# Note: Pritunl ecoute en HTTPS sur 443 avec cert self-signed.
# On va checker le port 443 mais en HTTPS avec acceptation des codes 2xx-4xx.
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "pritunl" {
  name     = "${local.name_prefix}-tg"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/check"
    protocol            = "HTTPS"
    port                = "443"
    matcher             = "200-499"
  }

  tags = {
    Name = "${local.name_prefix}-tg"
  }
}

# -----------------------------------------------------------------------------
# Listener HTTP - forward direct vers les instances Pritunl
# -----------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.pritunl.arn
  }
}

# Note: les providers tls/archive sont declares dans main.tf