##############################################################################
# Internet Gateway
#
# Replica de AulaRemota-IGW (igw-052c3ce487bb841cc), attachado a la VPC nueva.
##############################################################################

resource "aws_internet_gateway" "demo_ar_igw" {
  vpc_id = aws_vpc.demo_ar_vpc.id

  tags = {
    Name = local.name.igw
  }
}
