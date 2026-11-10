##############################################################################
# Outputs
##############################################################################

output "vpc_id" {
  description = "ID de la VPC nueva demo-ar-vpc-1.1."
  value       = aws_vpc.demo_ar_vpc.id
}

output "vpc_ipv6_cidr_block" {
  description = "Prefijo IPv6 /56 asignado por AWS a la VPC nueva (distinto del original)."
  value       = aws_vpc.demo_ar_vpc.ipv6_cidr_block
}

output "subnet_id" {
  description = "ID de la subnet publica demo-ar-subnet-1.1."
  value       = aws_subnet.demo_ar_subnet_1.id
}

output "subnet_ipv6_cidr_block" {
  description = "Prefijo IPv6 /64 de la subnet."
  value       = aws_subnet.demo_ar_subnet_1.ipv6_cidr_block
}

output "internet_gateway_id" {
  description = "ID del Internet Gateway demo-ar-igw-1.1."
  value       = aws_internet_gateway.demo_ar_igw.id
}

output "route_table_id" {
  description = "ID de la route table publica demo-ar-rt-1.1."
  value       = aws_route_table.demo_ar_rt_public.id
}

output "security_group_id" {
  description = "ID del security group demo-ar-sg-1.1."
  value       = aws_security_group.demo_ar_sg.id
}

output "instance_id" {
  description = "ID de la instancia EC2 demo-ar-ec2-1.1."
  value       = aws_instance.demo_ar_ec2.id
}

output "instance_private_ip" {
  description = "IP privada de la instancia."
  value       = aws_instance.demo_ar_ec2.private_ip
}

output "instance_ipv6_address" {
  description = "IPv6 publica de la instancia."
  value       = try(aws_instance.demo_ar_ec2.ipv6_addresses[0], null)
}

output "eip_public_ip" {
  description = "IP publica de la Elastic IP nueva. NO es la 54.164.93.74 del original."
  value       = aws_eip.demo_ar_eip.public_ip
}

output "lab_fqdn" {
  description = <<-EOT
    Nombre publico previsto (No-IP). Terraform NO lo gestiona.
    Despues del apply, entra al panel de No-IP y apunta este host a la IP que
    sale en "eip_public_ip". Comprueba que resuelve antes de pedir el
    certificado en Nginx Proxy Manager:
      Resolve-DnsName lab.example.com -Server 8.8.8.8
  EOT
  value       = local.lab_fqdn
}

output "siguiente_paso" {
  description = "Que hacer justo despues del apply."
  value = join("\n", [
    "1. En No-IP: apunta ${local.lab_fqdn} -> ${aws_eip.demo_ar_eip.public_ip}",
    "2. Comprueba que resuelve:  nslookup ${local.lab_fqdn} 8.8.8.8",
    "3. cd ansible && ansible-playbook site.yml",
    "4. Abre http://${aws_eip.demo_ar_eip.public_ip}:81 y crea el proxy host + certificado",
  ])
}

output "ssh_command" {
  description = "Comando de conexion sugerido (requiere que admin_cidr sea tu IP publica actual)."
  value = var.key_pair_name == null ? "Instancia creada sin key pair: no hay acceso SSH por clave." : (
    "ssh -i ~/.ssh/${var.key_pair_name}.pem ubuntu@${aws_eip.demo_ar_eip.public_ip}"
  )
}

output "api_url" {
  description = "URL base de la API de supervision que consume la app movil."
  value       = var.api_expuesta ? "http://${aws_eip.demo_ar_eip.public_ip}:8000" : "cerrada (api_expuesta = false)"
}
