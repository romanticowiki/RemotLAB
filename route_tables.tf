##############################################################################
# Route tables
#
# El original tiene dos:
#   - rtb-042df350def6d5605  main, sin tags, solo rutas "local"  -> la crea AWS
#   - rtb-0d88ba59d9299eb0e  "Subnet1-AR-RT", con salida a Internet v4 y v6
##############################################################################

# Replica de Subnet1-AR-RT.
# Las rutas "local" (10.0.77.0/24 y el /56 IPv6) NO se declaran: AWS las crea
# siempre de forma implicita y Terraform las ignora.
resource "aws_route_table" "demo_ar_rt_public" {
  vpc_id = aws_vpc.demo_ar_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo_ar_igw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.demo_ar_igw.id
  }

  tags = {
    Name = local.name.rt
  }
}

resource "aws_route_table_association" "demo_ar_rta_subnet_1" {
  subnet_id      = aws_subnet.demo_ar_subnet_1.id
  route_table_id = aws_route_table.demo_ar_rt_public.id
}

##############################################################################
# Route table main
#
# En el original, la tabla main es la que AWS crea junto con la VPC: no tiene
# tags y solo tiene rutas "local". aws_main_route_table_association sirve para
# APUNTAR la asociacion main a OTRA tabla, cosa que aqui no ocurre, y su uso
# provocaria diffs perpetuos.
#
# El recurso correcto es aws_default_route_table: adopta la tabla existente para
# poder etiquetarla y, en el destroy, simplemente sale del state (AWS la borra
# junto con la VPC). Ningun recurso huerfano.
##############################################################################

resource "aws_default_route_table" "demo_ar_rt_main" {
  default_route_table_id = aws_vpc.demo_ar_vpc.default_route_table_id

  # Sin rutas explicitas: igual que el original, solo las "local" implicitas.
  route = []

  tags = {
    Name = local.name.rt_main
  }
}
