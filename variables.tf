variable "aws_region" {
  description = "Region de AWS para el despliegue de la POC."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo del nombre de proyecto para nombrar recursos."
  type        = string
  default     = "innovatech-poc"
}

variable "environment" {
  description = "Etiqueta de entorno."
  type        = string
  default     = "poc"
}

variable "vpc_cidr" {
  description = "Bloque CIDR de la VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Bloque CIDR para la subred publica de frontend."
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "Bloque CIDR para la subred privada de backend/data."
  type        = string
  default     = "10.0.2.0/24"
}

variable "availability_zone" {
  description = "AZ fija opcional. Dejar vacio para elegir la primera disponible."
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "Tipo de instancia EC2 para todas las capas."
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "Nombre opcional del par de llaves EC2 para acceso SSH."
  type        = string
  default     = vockey
}

variable "ssh_allowed_cidr" {
  description = "CIDR permitido para acceso SSH al frontend."
  type        = string
  default     = "0.0.0.0/0"
}

variable "database_port" {
  description = "Puerto de base de datos expuesto por SG Data (5432 PostgreSQL o 3306 MySQL)."
  type        = number
  default     = 5432

  validation {
    condition     = contains([3306, 5432], var.database_port)
    error_message = "database_port debe ser 3306 (MySQL) o 5432 (PostgreSQL)."
  }
}

variable "extra_tags" {
  description = "Etiquetas adicionales para mezclar en todos los recursos."
  type        = map(string)
  default     = {}
}

variable "create_iam_resources" {
  description = "Si es true, Terraform crea rol/politica/profile IAM para EC2. Si es false, usar existing_instance_profile_arn."
  type        = bool
  default     = true
}

variable "existing_instance_profile" {
  description = "Instance Profile existente para EC2 cuando create_iam_resources=false. Puede ser ARN o nombre."
  type        = string
  default     = null
}
