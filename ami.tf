##############################################################################
# AMI de Ubuntu 22.04
#
# El repo original fijaba ami-0030e4319cbf4dbf2. Ese ID solo existe en la
# region donde se capturo y puede dejar de estar disponible; en una cuenta
# nueva el apply falla con "InvalidAMIID.NotFound" sin explicar por que.
#
# Aqui se busca por nombre en el propietario oficial de Canonical
# (099720109477), asi que funciona en cualquier region y siempre trae la
# imagen mas reciente con los parches al dia.
#
# Si prefieres fijar una AMI concreta, pon su ID en var.ami_id y este data
# source se ignora.
##############################################################################

data "aws_ami" "ubuntu_2204" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  ami_efectiva = coalesce(var.ami_id, data.aws_ami.ubuntu_2204.id)
}
