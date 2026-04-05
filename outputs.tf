output "vpc_id" {
  description = "ID de la VPC principal."
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID de la subred publica de frontend."
  value       = aws_subnet.public_frontend.id
}

output "private_subnet_id" {
  description = "ID de la subred privada de backend/data."
  value       = aws_subnet.private_backend_data.id
}

output "frontend_public_ip" {
  description = "Direccion IP publica de la instancia EC2 frontend."
  value       = aws_instance.frontend.public_ip
}

output "backend_private_ip" {
  description = "Direccion IP privada de la instancia EC2 backend."
  value       = aws_instance.backend.private_ip
}

output "data_private_ip" {
  description = "Direccion IP privada de la instancia EC2 data."
  value       = aws_instance.data.private_ip
}

output "security_group_ids" {
  description = "Grupos de seguridad por cada capa."
  value = {
    front = aws_security_group.sg_front.id
    back  = aws_security_group.sg_back.id
    data  = aws_security_group.sg_data.id
  }
}
