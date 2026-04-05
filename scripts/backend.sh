#!/bin/bash
set -euxo pipefail

exec > >(tee /var/log/user-data.log) 2>&1

# Actualizaciones de seguridad y paquetes
yum update -y --security || yum update -y

# Herramientas base
amazon-linux-extras install docker -y
yum install -y git

# Habilitar e iniciar Docker
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user
