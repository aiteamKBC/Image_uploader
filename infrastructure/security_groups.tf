# One security group shared by the load balancer AND the app tasks
resource "aws_security_group" "image_uploader_sg" {
  name        = "iu-sg"
  description = "Image uploader - load balancer and app tasks"
  vpc_id      = aws_default_vpc.image_uploader_vpc.id
}

# Internet -> load balancer on HTTP
resource "aws_vpc_security_group_ingress_rule" "http_in" {
  security_group_id = aws_security_group.image_uploader_sg.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

# Load balancer -> app on 8023: only from resources that also have this group
resource "aws_vpc_security_group_ingress_rule" "app_from_self" {
  security_group_id            = aws_security_group.image_uploader_sg.id
  ip_protocol                  = "tcp"
  from_port                    = 8023
  to_port                      = 8023
  referenced_security_group_id = aws_security_group.image_uploader_sg.id
}

# All outbound: forward to the app, pull from ECR, call Supabase
resource "aws_vpc_security_group_egress_rule" "all_out" {
  security_group_id = aws_security_group.image_uploader_sg.id
  ip_protocol       = "-1" # -1 = all traffic
  cidr_ipv4         = "0.0.0.0/0"
}
