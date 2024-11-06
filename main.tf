provider "aws" {
  region = "ap-northeast-2"
}

# VPC
resource "aws_vpc" "myproject_prod_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name              = "myproject-prod-vpc"
    ManagedBy         = "Terraform"
    ModificationLocked = "true"
  }
}

# Public Subnet for NAT Gateway
resource "aws_subnet" "myproject_prod_public_subnet" {
  vpc_id            = aws_vpc.myproject_prod_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-northeast-2a"

  tags = {
    Name              = "myproject-prod-public-subnet"
    ManagedBy         = "Terraform"
    ModificationLocked = "true"
  }
}

# Private Subnet
resource "aws_subnet" "myproject_prod_private_subnet" {
  vpc_id            = aws_vpc.myproject_prod_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-northeast-2a"

  tags = {
    Name              = "myproject-prod-private-subnet"
    ManagedBy         = "Terraform"
    ModificationLocked = "true"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "myproject_prod_igw" {
  vpc_id = aws_vpc.myproject_prod_vpc.id

  tags = {
    Name              = "myproject-prod-igw"
    ManagedBy         = "Terraform"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "myproject_prod_eip" {
  domain = "vpc"

  tags = {
    Name              = "myproject-prod-eip"
    ManagedBy         = "Terraform"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "myproject_prod_nat_gateway" {
  allocation_id = aws_eip.myproject_prod_eip.id
  subnet_id     = aws_subnet.myproject_prod_public_subnet.id

  tags = {
    Name              = "myproject-prod-nat-gateway"
    ManagedBy         = "Terraform"
  }
}

# Public Route Table
resource "aws_route_table" "myproject_prod_public_rt" {
  vpc_id = aws_vpc.myproject_prod_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.myproject_prod_igw.id
  }

  tags = {
    Name              = "myproject-prod-public-rt"
    ManagedBy         = "Terraform"
  }
}

# Associate Route Table with Public Subnet
resource "aws_route_table_association" "myproject_prod_public_rt_association" {
  subnet_id      = aws_subnet.myproject_prod_public_subnet.id
  route_table_id = aws_route_table.myproject_prod_public_rt.id
}

# Private Route Table
resource "aws_route_table" "myproject_prod_private_rt" {
  vpc_id = aws_vpc.myproject_prod_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.myproject_prod_nat_gateway.id
  }

  tags = {
    Name              = "myproject-prod-private-rt"
    ManagedBy         = "Terraform"
  }
}

# Associate Route Table with Private Subnet
resource "aws_route_table_association" "myproject_prod_private_rt_association" {
  subnet_id      = aws_subnet.myproject_prod_private_subnet.id
  route_table_id = aws_route_table.myproject_prod_private_rt.id
}

# IAM Role for SSM Access
resource "aws_iam_role" "myproject_prod_ssm_role" {
  name = "myproject-prod-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    ManagedBy         = "Terraform"
    ModificationLocked = "true"
  }
}

# Attach SSM Policy to IAM Role
resource "aws_iam_role_policy_attachment" "myproject_prod_ssm_policy_attachment" {
  role       = aws_iam_role.myproject_prod_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Instance Profile for EC2
resource "aws_iam_instance_profile" "myproject_prod_ssm_profile" {
  name = "myproject-prod-ssm-instance-profile"
  role = aws_iam_role.myproject_prod_ssm_role.name

  tags = {
    ManagedBy         = "Terraform"
    ModificationLocked = "true"
  }
}

# Security Group for VPC Endpoints (Dedicated for VPC Endpoints)
resource "aws_security_group" "myproject_prod_vpc_endpoint_sg" {
  name        = "myproject-prod-vpc-endpoint-sg"
  description = "Security group for VPC Endpoints"
  vpc_id      = aws_vpc.myproject_prod_vpc.id

  # Ingress rule: Allow only HTTPS traffic for SSM and other services
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]  # Only allow traffic within the VPC
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name              = "myproject-prod-vpc-endpoint-sg"
    ManagedBy         = "Terraform"
    ModificationLocked = "true"
  }
}

# Security Group for EC2 Instance (Allow access only from SSM)
resource "aws_security_group" "myproject_prod_ec2_sg" {
  name        = "myproject-prod-ec2-sg"
  description = "Security group for EC2 to allow SSM access"
  vpc_id      = aws_vpc.myproject_prod_vpc.id

  # Ingress rule: Allow HTTPS traffic from the VPC Endpoint's security group
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [aws_security_group.myproject_prod_vpc_endpoint_sg.id]  # Only allow traffic from VPC endpoint
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name              = "myproject-prod-ec2-sg"
    ManagedBy         = "Terraform"
    ModificationLocked = "true"
  }
}

# EC2 Instance in Private Subnet
resource "aws_instance" "myproject_prod_private_instance" {
  ami                    = "ami-01123b84e2a4fba05"  # Amazon Linux 2 in ap-northeast-2
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.myproject_prod_private_subnet.id
  associate_public_ip_address = false
  security_groups        = [aws_security_group.myproject_prod_ec2_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.myproject_prod_ssm_profile.name

  # SSM Agent install script
  user_data = <<-EOF
    #!/bin/bash
    yum install -y amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
  EOF

  tags = {
    Name              = "myproject-prod-private-instance"
    ManagedBy         = "Terraform"
    ModificationLocked = "true"
  }
}

# VPC Endpoint for SSM
resource "aws_vpc_endpoint" "myproject_prod_ssm_endpoint" {
  vpc_id            = aws_vpc.myproject_prod_vpc.id
  service_name      = "com.amazonaws.ap-northeast-2.ssm"
  vpc_endpoint_type = "Interface"
  subnet_ids        = [aws_subnet.myproject_prod_private_subnet.id]
  security_group_ids = [aws_security_group.myproject_prod_vpc_endpoint_sg.id]

  tags = {
    ManagedBy         = "Terraform"
    ModificationLocked = "true"
  }
}

# VPC Endpoint for SSM Messages
resource "aws_vpc_endpoint" "myproject_prod_ssmmessages_endpoint" {
  vpc_id            = aws_vpc.myproject_prod_vpc.id
  service_name      = "com.amazonaws.ap-northeast-2.ssmmessages"
  vpc_endpoint_type = "Interface"
  subnet_ids        = [aws_subnet.myproject_prod_private_subnet.id]
  security_group_ids = [aws_security_group.myproject_prod_vpc_endpoint_sg.id]

  tags = {
    ManagedBy         = "Terraform"
    ModificationLocked = "true"
  }
}

# VPC Endpoint for EC2 Messages
resource "aws_vpc_endpoint" "myproject_prod_ec2messages_endpoint" {
  vpc_id            = aws_vpc.myproject_prod_vpc.id
  service_name      = "com.amazonaws.ap-northeast-2.ec2messages"
  vpc_endpoint_type = "Interface"
  subnet_ids        = [aws_subnet.myproject_prod_private_subnet.id]
  security_group_ids = [aws_security_group.myproject_prod_vpc_endpoint_sg.id]

  tags = {
    ManagedBy         = "Terraform"
    ModificationLocked = "true"
  }
}

# Prowler Automation
resource "null_resource" "run_prowler" {
  depends_on = [aws_vpc_endpoint.myproject_prod_ssm_endpoint, aws_vpc_endpoint.myproject_prod_ssmmessages_endpoint, aws_vpc_endpoint.myproject_prod_ec2messages_endpoint]

  provisioner "local-exec" {
    command = <<-EOT
      # Delete existing file
      rm -f prowler-report.json prowler-error.log
        
      # Refresh SSO login session and verify authentication session
      aws sso login --profile AdministratorAccess-756209548001 || true
      sleep 5
        
      # Run Prowler
      prowler aws --profile AdministratorAccess-756209548001 > prowler-report.txt 2> prowler-error.log
    EOT
  }
}

