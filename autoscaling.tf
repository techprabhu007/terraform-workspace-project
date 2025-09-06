# ------------------------------------------------------------------------------------------------
# SECURITY GROUPS (Crucial for Security)
# ------------------------------------------------------------------------------------------------

# Security group for the Application Load Balancer
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg-${terraform.workspace}"
  description = "Allow HTTP traffic from the internet to the ALB"
  vpc_id      = aws_vpc.main.id

  # Allow inbound HTTP traffic from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg-${terraform.workspace}"
  }
}

# Security group for the EC2 instances in the ASG
resource "aws_security_group" "ec2_sg" {
  name        = "${var.project_name}-ec2-sg-${terraform.workspace}"
  description = "Allow HTTP traffic from the ALB to the EC2 instances"
  vpc_id      = aws_vpc.main.id

  # Allow inbound HTTP traffic ONLY from the ALB's security group
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Allow all outbound traffic (for downloading updates, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ec2-sg-${terraform.workspace}"
  }
}

# ------------------------------------------------------------------------------------------------
# APPLICATION TIER (ASG & ALB)
# ------------------------------------------------------------------------------------------------

# Launch Template for the Auto Scaling Group instances
resource "aws_launch_template" "asg_lt" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = "ami-0c7217cdde317cfec" # Amazon Linux 2 AMI in us-east-1
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  # This script installs a simple Apache web server to respond to health checks
  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello World from $(hostname -f)</h1>" > /var/www/html/index.html
              EOF
  )

  tags = {
    Name = "${var.project_name}-launch-template-${terraform.workspace}"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "asg" {
  name                 = "${var.project_name}-asg-${terraform.workspace}"
  desired_capacity     = var.asg_desired_capacity
  max_size             = var.asg_max_size
  min_size             = var.asg_min_size
  
  # The ASG needs a list of all private subnet IDs
  vpc_zone_identifier  = values(aws_subnet.private)[*].id

  launch_template {
    id      = aws_launch_template.asg_lt.id
    version = "$Latest"
  }

  # This is the modern way to attach a target group
  target_group_arns = [aws_lb_target_group.tg.arn]

  tag {
    key                 = "Name" # Corrected tag key
    value               = "${var.project_name}-asg-instance"
    propagate_at_launch = true
  }
}

# Application Load Balancer
resource "aws_lb" "alb" {
  name               = "${var.project_name}-alb-${terraform.workspace}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]

  # The ALB needs a list of all public subnet IDs
  subnets            = values(aws_subnet.public)[*].id
}

# Target Group for the ALB
resource "aws_lb_target_group" "tg" {
  name     = "${var.project_name}-tg-${terraform.workspace}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  # Add a health check so the ALB knows which instances are healthy
  health_check {
    enabled             = true
    path                = "/index.html"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 10
  }
}

# ALB Listener for HTTP traffic
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}