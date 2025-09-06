# Fetch available Availability Zones in the current region
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # Enables DNS hostnames, required for some AWS services
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc-${terraform.workspace}"
  }
}

resource "aws_subnet" "public" {
  # Use for_each to create one public subnet in each of our desired AZs (first two available)
  for_each = toset(slice(data.aws_availability_zones.available.names, 0, 2))

  vpc_id                  = aws_vpc.main.id
  # Use cidrsubnet to calculate a unique CIDR block for each subnet
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, index(data.aws_availability_zones.available.names, each.value) + 10)
  availability_zone       = each.value
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${each.value}-${terraform.workspace}"
  }
}

resource "aws_subnet" "private" {
  # Create one private subnet in each of our desired AZs
  for_each = toset(slice(data.aws_availability_zones.available.names, 0, 2))

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, index(data.aws_availability_zones.available.names, each.value) + 20)
  availability_zone = each.value

  tags = {
    Name = "${var.project_name}-private-${each.value}-${terraform.workspace}"
  }
}


resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.project_name}-igw-${terraform.workspace}"
  }
}

resource "aws_eip" "nat_eip" {
  # "domain" is the modern syntax, replacing the legacy "vpc = true"
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  # Place the NAT Gateway in the first public subnet
  subnet_id     = aws_subnet.public[data.aws_availability_zones.available.names[0]].id
  allocation_id = aws_eip.nat_eip.id

  tags = {
    Name = "${var.project_name}-nat-${terraform.workspace}"
  }

  # Ensure the Internet Gateway is created and attached before the NAT Gateway
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  # Public route table points all outbound traffic (0.0.0.0/0) to the Internet Gateway
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.project_name}-public-rt-${terraform.workspace}"
  }
}

resource "aws_route_table_association" "public_assoc" {
  # Associate the public route table with all public subnets
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  # Private route table points all outbound traffic (0.0.0.0/0) to the NAT Gateway
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "${var.project_name}-private-rt-${terraform.workspace}"
  }
}

resource "aws_route_table_association" "private_assoc" {
  # Associate the private route table with all private subnets
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_rt.id
}