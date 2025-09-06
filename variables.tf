variable "aws_region" {}
variable "project_name" {}

# VPC
variable "vpc_cidr" {}
variable "public_subnet_cidr" {}
variable "private_subnet_cidr" {}

# EC2
variable "instance_type" {}
variable "key_name" {}

# ASG
variable "asg_desired_capacity" { default = 2 }
variable "asg_min_size" { default = 1 }
variable "asg_max_size" { default = 3 }
