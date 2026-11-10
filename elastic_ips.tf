##############################################################################
# Elastic IP
#
# Replica de eipalloc-06dcbb35e6bcb91c8 / eipassoc-07ac4baad1672e1c7.
#
# La IP publica nueva NO sera 54.164.93.74: AWS asigna una distinta. Todos los
# registros DNS de route53.tf referencian aws_eip.demo_ar_eip.public_ip, nunca la
# IP literal del original.
##############################################################################

resource "aws_eip" "demo_ar_eip" {
  domain = "vpc"

  tags = {
    Name = local.name.eip
  }

  # La EIP necesita que el IGW este attachado antes de asociarse, y que se libere
  # antes de que el IGW desaparezca en el destroy.
  depends_on = [aws_internet_gateway.demo_ar_igw]
}

# En el original la EIP esta asociada a la ENI de la instancia. Usar instance_id
# es equivalente y mas simple, porque esa ENI la crea la propia instancia.
resource "aws_eip_association" "demo_ar_eip_assoc" {
  allocation_id = aws_eip.demo_ar_eip.id
  instance_id   = aws_instance.demo_ar_ec2.id
}
