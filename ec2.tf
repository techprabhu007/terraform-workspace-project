resource "aws_instance" "bastion" {
  ami           = "ami-0c7217cdde317cfec" # Replace with a valid AMI for your region
  instance_type = var.instance_type
  key_name      = var.key_name

  # Correctly reference the ID of the first public subnet in the map
  subnet_id = aws_subnet.public[data.aws_availability_zones.available.names[0]].id
  
  # Ensure the bastion gets a public IP
  associate_public_ip_address = true
  
  # You should create and assign a dedicated security group for the bastion
  # vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  tags = {
    Name = "${var.project_name}-bastion-${terraform.workspace}"
  }
}