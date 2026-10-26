# The load balancer itself (console: EC2 -> Load balancers -> Create ALB)
resource "aws_lb" "image_uploader_alb" {
  name               = "iu-alb"
  load_balancer_type = "application"
  internal           = false # internet-facing

  security_groups = [aws_security_group.image_uploader_sg.id]

  # The 3 default subnets you declared in main.tf (one per availability zone)
  subnets = [
    aws_default_subnet.image_uploader_subnet_a.id,
    aws_default_subnet.image_uploader_subnet_b.id,
    aws_default_subnet.image_uploader_subnet_c.id,
  ]

  idle_timeout = 300 # big uploads need more than the 60s default
}

# Target group: the list of app containers the ALB sends traffic to
resource "aws_lb_target_group" "image_uploader_tg" {
  name        = "iu-backend-tg"
  port        = 8023
  protocol    = "HTTP"
  target_type = "ip" # required for Fargate
  vpc_id      = aws_default_vpc.image_uploader_vpc.id

  deregistration_delay = 30 # faster deploys than the 300s default

  health_check {
    path                = "/health/" # backend/config/health.py
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }
}

# Listener: "on port 80, forward everything to the target group"
resource "aws_lb_listener" "image_uploader_http" {
  load_balancer_arn = aws_lb.image_uploader_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.image_uploader_tg.arn
  }
}

output "alb_dns_name" {
  value = aws_lb.image_uploader_alb.dns_name
}
