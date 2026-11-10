##############################################################################
# Subnet publica
#
# Replica de subnetAR-first (subnet-0c0302f83c097aaba).
#
# Nota: el output de describe-network-acls revela una SEGUNDA subnet en la VPC
# original (subnet-02966186f50117800) que no aparece en describe-subnets. Por
# decision explicita no se replica.
##############################################################################

resource "aws_subnet" "demo_ar_subnet_1" {
  vpc_id            = aws_vpc.demo_ar_vpc.id
  cidr_block        = var.subnet_cidr
  availability_zone = var.availability_zone

  # El original usa 2600:1f10:49ae:e101::/64 dentro del /56 ...e100::/56,
  # es decir el /64 de indice 1. cidrsubnet(/56, 8, 1) reproduce esa posicion
  # sobre el prefijo nuevo que asigne AWS.
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.demo_ar_vpc.ipv6_cidr_block, 8, 1)
  assign_ipv6_address_on_creation = true
  ipv6_native                     = false
  enable_dns64                    = false

  map_public_ip_on_launch = true

  private_dns_hostname_type_on_launch            = "ip-name"
  enable_resource_name_dns_a_record_on_launch    = false
  enable_resource_name_dns_aaaa_record_on_launch = false

  tags = {
    Name = local.name.subnet
  }
}
