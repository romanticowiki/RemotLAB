##############################################################################
# VPC
#
# Replica de vpc-aularemota (vpc-02da4f643ebca0904) como recurso NUEVO.
# El DhcpOptionsId del original (dopt-00498a2614dd8b0a4) es el set default de la
# cuenta: no se gestiona, la VPC nueva lo recibe automaticamente.
##############################################################################

resource "aws_vpc" "demo_ar_vpc" {
  cidr_block       = var.vpc_cidr
  instance_tenancy = "default"

  # El original tiene un /56 IPv6 del pool de Amazon (Ipv6Pool = "Amazon").
  # El prefijo nuevo sera distinto: lo asigna AWS.
  assign_generated_ipv6_cidr_block = true

  # No aparecen en describe-vpcs (harian falta describe-vpc-attribute), pero se
  # deducen de que la instancia original tiene PrivateDnsName y PublicDnsName.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = local.name.vpc
  }
}

##############################################################################
# Recursos "default" de la VPC
#
# AWS los crea automaticamente junto con la VPC. NO se pueden crear ni borrar de
# forma independiente, solo adoptar y modificar. Usar los recursos aws_default_*
# es lo que garantiza un terraform destroy limpio: salen del state y AWS los
# elimina junto con la VPC.
##############################################################################

# El SG default no aparece en el JSON (describe-security-groups se filtro por el
# SG de la instancia), pero toda VPC tiene uno. Se declara sin bloques ingress ni
# egress, lo que revoca TODAS sus reglas y lo deja bloqueado. La instancia usa su
# propio SG (demo-ar-sg-1.1), asi que este queda sin uso.
resource "aws_default_security_group" "demo_ar_sg_default" {
  vpc_id = aws_vpc.demo_ar_vpc.id

  tags = {
    Name = local.name.sg_default
  }
}
