##############################################################################
# Network ACL
#
# El unico NACL del original (acl-0c5a8fc8be8fc0f69) tiene IsDefault = true y sus
# reglas son exactamente las de fabrica. Por eso se usa aws_default_network_acl y
# no aws_network_acl: el NACL default no se puede crear ni borrar, solo adoptar y
# modificar. En el destroy sale del state y AWS lo elimina con la VPC.
#
# Las reglas 32767 (IPv4) y 32768 (IPv6) con RuleAction "deny" NO se declaran:
# son el deny implicito que AWS anade siempre y no es gestionable.
#
# subnet_ids se omite deliberadamente: AWS asocia toda subnet nueva al NACL
# default por si sola (que es justo el estado del original), y declararlo aqui
# genera diffs perpetuos entre el provider y AWS.
##############################################################################

resource "aws_default_network_acl" "demo_ar_nacl" {
  default_network_acl_id = aws_vpc.demo_ar_vpc.default_network_acl_id

  ingress {
    rule_no    = 100
    action     = "allow"
    protocol   = "-1"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  ingress {
    rule_no         = 101
    action          = "allow"
    protocol        = "-1"
    ipv6_cidr_block = "::/0"
    from_port       = 0
    to_port         = 0
  }

  egress {
    rule_no    = 100
    action     = "allow"
    protocol   = "-1"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    rule_no         = 101
    action          = "allow"
    protocol        = "-1"
    ipv6_cidr_block = "::/0"
    from_port       = 0
    to_port         = 0
  }

  tags = {
    Name = local.name.nacl
  }

  lifecycle {
    # AWS asocia las subnets nuevas a este NACL automaticamente; ignorarlo evita
    # que Terraform intente "desasociarlas" en cada plan.
    ignore_changes = [subnet_ids]
  }
}
