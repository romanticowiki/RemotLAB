locals {
  prefix = "demo-ar"
  suffix = "1.1"

  # Los labels de recurso de Terraform no admiten puntos, pero los tags "Name" si.
  # Ejemplo: local.name.vpc => "demo-ar-vpc-1.1"
  name = {
    vpc        = "${local.prefix}-vpc-${local.suffix}"
    subnet     = "${local.prefix}-subnet-${local.suffix}"
    igw        = "${local.prefix}-igw-${local.suffix}"
    rt         = "${local.prefix}-rt-${local.suffix}"
    rt_main    = "${local.prefix}-rt-main-${local.suffix}"
    nacl       = "${local.prefix}-nacl-${local.suffix}"
    sg         = "${local.prefix}-sg-${local.suffix}"
    sg_default = "${local.prefix}-sg-default-${local.suffix}"
    eip        = "${local.prefix}-eip-${local.suffix}"
    ec2        = "${local.prefix}-ec2-${local.suffix}"
  }

  # Nombre publico de la instancia. Con No-IP, Terraform no gestiona el DNS:
  # el registro lo mantiene No-IP y hay que apuntarlo a mano a la Elastic IP.
  # Se conserva como local para no tocar todos los sitios que ya lo usaban.
  lab_fqdn = var.lab_fqdn
}
