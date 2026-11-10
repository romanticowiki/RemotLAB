##############################################################################
# Instancia EC2
#
# Replica de aularemota-aws-instance (i-0068af22426a78974).
#
# Se omiten a proposito:
#   - availability_zone: la determina subnet_id; declararlo es redundante y puede
#     provocar conflictos.
#   - cpu_options: CoreCount 1 / ThreadsPerCore 2 es el default exacto de
#     m7i-flex.large, y declararlo forzaria recreaciones al cambiar instance_type.
#   - BootMode "uefi-preferred": viene de la AMI, no es configurable en el recurso.
#
# La instancia original esta "stopped"; Terraform la creara arrancada.
##############################################################################

resource "aws_instance" "demo_ar_ec2" {
  ami           = local.ami_efectiva
  instance_type = var.instance_type
  key_name      = var.key_pair_name

  subnet_id              = aws_subnet.demo_ar_subnet_1.id
  vpc_security_group_ids = [aws_security_group.demo_ar_sg.id]
  # Fija a 10.0.77.58, la misma que tenia la instancia original. El dump de la BD
  # de Guacamole guarda las conexiones VNC apuntando a esa IP, asi que se restaura
  # sin editarlo. Ver variables.tf para el detalle. Cambiarlo recrea la instancia.
  private_ip = var.private_ip

  associate_public_ip_address = true
  ipv6_address_count          = 1

  ebs_optimized     = true
  monitoring        = false
  source_dest_check = true
  hibernation       = false

  # describe-instances no devuelve DisableApiTermination (haria falta
  # describe-instance-attribute), asi que el valor del original es desconocido.
  # Se fijan ambos a false explicitamente para garantizar que terraform destroy
  # pueda terminar la instancia sin intervencion manual.
  disable_api_termination = false
  disable_api_stop        = false

  instance_initiated_shutdown_behavior = "stop"

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"

    # Clave para el destroy: el volumen desaparece con la instancia y no queda
    # ningun EBS huerfano. Coincide con el original.
    delete_on_termination = true

    tags = {
      Name = "${local.prefix}-root-${local.suffix}"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    http_protocol_ipv6          = "disabled"
    instance_metadata_tags      = "disabled"
  }

  private_dns_name_options {
    hostname_type                        = "ip-name"
    enable_resource_name_dns_a_record    = false
    enable_resource_name_dns_aaaa_record = false
  }

  enclave_options {
    enabled = false
  }

  maintenance_options {
    auto_recovery = "default"
  }

  tags = {
    Name = local.name.ec2
  }
}
