terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

locals {
  common_tags = merge(
    {
      Project     = "innovatech-lift-shift-poc"
      Company     = "Innovatech Chile"
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.extra_tags
  )

  az_name = var.availability_zone != "" ? var.availability_zone : data.aws_availability_zones.available.names[0]

  use_instance_profile       = false
  instance_profile_arn_value = null
  instance_profile_name      = null
}

# ----------------------------------------------------
# Red
# ----------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

resource "aws_subnet" "public_frontend" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = local.az_name
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-frontend"
    Tier = "frontend"
  })
}

resource "aws_subnet" "private_backend_data" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = local.az_name
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-backend-data"
    Tier = "backend-data"
  })
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nat-eip"
  })
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_frontend.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nat"
  })

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-rt"
  })
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_frontend.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-rt"
  })
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private_backend_data.id
  route_table_id = aws_route_table.private_rt.id
}

# ----------------------------------------------------
# Grupos de seguridad
# ----------------------------------------------------
resource "aws_security_group" "sg_front" {
  name        = "${var.project_name}-sg-front"
  description = "SG Frontend: HTTP publico y SSH restringido"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP desde internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH restringido"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-sg-front"
  })
}

resource "aws_security_group" "sg_back" {
  name        = "${var.project_name}-sg-back"
  description = "SG Backend: solo desde SG Frontend"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Trafico de aplicacion desde frontend"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_front.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-sg-back"
  })
}

resource "aws_security_group" "sg_data" {
  name        = "${var.project_name}-sg-data"
  description = "SG Data: acceso a BD solo desde SG Backend"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Base de datos desde backend"
    from_port       = var.database_port
    to_port         = var.database_port
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_back.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-sg-data"
  })
}

# ----------------------------------------------------
# Launch Templates
# ----------------------------------------------------
resource "aws_launch_template" "lt_front" {
  name_prefix   = "${var.project_name}-lt-front-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type
  key_name      = var.key_name

  network_interfaces {
    subnet_id                   = aws_subnet.public_frontend.id
    associate_public_ip_address = true
    security_groups             = [aws_security_group.sg_front.id]
  }

  user_data = filebase64("${path.module}/scripts/frontend.sh")

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${var.project_name}-front"
      Tier = "frontend"
    })
  }
}

resource "aws_launch_template" "lt_back" {
  name_prefix   = "${var.project_name}-lt-back-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type
  key_name      = var.key_name

  network_interfaces {
    subnet_id                   = aws_subnet.private_backend_data.id
    associate_public_ip_address = false
    security_groups             = [aws_security_group.sg_back.id]
  }

  user_data = filebase64("${path.module}/scripts/backend.sh")

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${var.project_name}-back"
      Tier = "backend"
    })
  }
}

resource "aws_launch_template" "lt_data" {
  name_prefix   = "${var.project_name}-lt-data-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type
  key_name      = var.key_name

  network_interfaces {
    subnet_id                   = aws_subnet.private_backend_data.id
    associate_public_ip_address = false
    security_groups             = [aws_security_group.sg_data.id]
  }

  user_data = filebase64("${path.module}/scripts/data.sh")

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${var.project_name}-data"
      Tier = "data"
    })
  }
}

# ----------------------------------------------------
# EC2
# ----------------------------------------------------
resource "aws_instance" "frontend" {
  launch_template {
    id      = aws_launch_template.lt_front.id
    version = "$Latest"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-frontend-instance"
  })
}

resource "aws_instance" "backend" {
  launch_template {
    id      = aws_launch_template.lt_back.id
    version = "$Latest"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-backend-instance"
  })
}

resource "aws_instance" "data" {
  launch_template {
    id      = aws_launch_template.lt_data.id
    version = "$Latest"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-data-instance"
  })
}