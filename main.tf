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
  use_instance_profile       = var.create_iam_resources || (var.existing_instance_profile != null && trimspace(var.existing_instance_profile) != "")
  existing_profile_is_arn    = var.existing_instance_profile != null ? can(regex("^arn:aws:iam::[0-9]{12}:instance-profile/.+", trimspace(var.existing_instance_profile))) : false
  instance_profile_arn_value = local.use_instance_profile ? (var.create_iam_resources ? aws_iam_instance_profile.ec2_instance_profile[0].arn : (local.existing_profile_is_arn ? trimspace(var.existing_instance_profile) : null)) : null
  instance_profile_name      = local.use_instance_profile ? (var.create_iam_resources ? null : (local.existing_profile_is_arn ? null : trimspace(var.existing_instance_profile))) : null
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
# Grupos de seguridad (Mínimo privilegio)
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
# Rol IAM para AWS Session Manager
# ----------------------------------------------------
resource "aws_iam_role" "ec2_ssm_role" {
  count = var.create_iam_resources ? 1 : 0
  name = "${var.project_name}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm_core_attachment" {
  count      = var.create_iam_resources ? 1 : 0
  role       = aws_iam_role.ec2_ssm_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  count = var.create_iam_resources ? 1 : 0
  name = "${var.project_name}-ec2-instance-profile"
  role = aws_iam_role.ec2_ssm_role[0].name
}

# ----------------------------------------------------
# Capa de computo (Launch Templates + instancias EC2)
# ----------------------------------------------------
resource "aws_launch_template" "lt_front" {
  name_prefix   = "${var.project_name}-lt-front-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type
  key_name      = var.key_name

  dynamic "iam_instance_profile" {
    for_each = local.use_instance_profile ? [1] : []
    content {
      arn  = local.instance_profile_arn_value
      name = local.instance_profile_name
    }
  }

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

  dynamic "iam_instance_profile" {
    for_each = local.use_instance_profile ? [1] : []
    content {
      arn  = local.instance_profile_arn_value
      name = local.instance_profile_name
    }
  }

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

  dynamic "iam_instance_profile" {
    for_each = local.use_instance_profile ? [1] : []
    content {
      arn  = local.instance_profile_arn_value
      name = local.instance_profile_name
    }
  }

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
