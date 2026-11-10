variable "aws_region" {
  description = "Region de AWS. El original vive en us-east-1 (visto en SubnetArn y AvailabilityZone)."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR IPv4 de la VPC. Original: Vpcs[0].CidrBlock."
  type        = string
  default     = "10.0.77.0/24"
}

variable "subnet_cidr" {
  description = "CIDR IPv4 de la subnet publica. Original: Subnets[0].CidrBlock."
  type        = string
  default     = "10.0.77.0/26"
}

variable "availability_zone" {
  description = "AZ de la subnet y por tanto de la instancia. Original: us-east-1a."
  type        = string
  default     = "us-east-1a"
}

variable "private_ip" {
  description = <<-EOT
    IP privada fija de la instancia, dentro de subnet_cidr.

    Se fija a la MISMA que tenia la instancia original (10.0.77.58) a proposito:
    el dump de la base de datos de Guacamole guarda las conexiones VNC apuntando
    a esa direccion, asi que restaurarlo funciona sin editar una sola linea del
    .sql. No hay conflicto porque las IPs privadas solo son unicas dentro de una
    VPC, y la original vive en otra VPC distinta.

    Beneficio adicional: la IP privada deja de cambiar en cada reconstruccion.

    Restricciones: debe estar dentro de 10.0.77.0/26 (o sea .0 a .63) y evitar las
    cinco que AWS reserva (.0, .1, .2, .3 y .63).

    OJO: cambiar este valor RECREA la instancia. La IP privada primaria de una ENI
    no se puede modificar en caliente. La Elastic IP y el registro DNS no se tocan.
  EOT
  type        = string
  default     = "10.0.77.58"
}

variable "instance_type" {
  description = <<-EOT
    Tipo de instancia EC2. Original: m7i-flex.large.
    Cambiarlo aqui (o en terraform.tfvars) NO recrea la instancia: Terraform la para,
    la modifica y la vuelve a arrancar. La EIP y el volumen raiz se conservan.
  EOT
  type        = string
  default     = "m7i-flex.large"
}

variable "ami_id" {
  # Poner un ID concreto solo si quieres fijar una AMI. Ver ami.tf.
  description = "AMI de la instancia. Original: ImageId ami-0030e4319cbf4dbf2 (Linux/UNIX, x86_64)."
  type        = string
  nullable    = true
  default     = null # null => se busca la Ubuntu 22.04 oficial (ver ami.tf)
}

variable "key_pair_name" {
  description = <<-EOT
    Nombre de un key pair YA EXISTENTE en la cuenta.
    Terraform solo lo referencia, nunca lo crea ni lo borra, asi que no afecta al destroy.
    Poner null para crear la instancia sin acceso SSH por clave.
  EOT
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Tamano del volumen raiz en GB. 30 GB gp3 es el limite del free tier."
  type        = number
  default     = 30
}

variable "admin_cidr" {
  description = <<-EOT
    CIDR de administracion, usado para SSH (22) y para el puerto 81.
    Original: 189.249.207.150/32, capturado el 2026-03-22.
    OJO: es una IP publica domestica y lo mas probable es que ya haya cambiado.
    Comprueba la tuya con "curl -4 ifconfig.me" y actualiza terraform.tfvars.
  EOT
  type        = string
  default     = "162.120.186.163/32"
}

variable "lab_fqdn" {
  description = <<-EOT
    Nombre publico de la instancia. Aqui es el host de No-IP.

    Terraform NO lo crea ni lo gestiona: es informativo, se usa en los outputs
    y lo consume Ansible como lab_fqdn. Quien mantiene el registro es No-IP, y
    hay que apuntarlo a mano a la Elastic IP que imprime "eip_public_ip".

    Es el nombre EXACTO para el que Nginx Proxy Manager pedira el certificado.
  EOT
  type        = string
  default     = "lab.example.com"
}

variable "api_expuesta" {
  description = <<-EOT
    Abre el puerto 8000 al exterior para que la app movil llegue a la API.

    TEMPORAL: el token viaja en HTTP plano. Ponlo en false en cuanto la API
    este publicada detras de Nginx Proxy Manager sobre el 443.
  EOT
  type        = bool
  default     = true
}

variable "guacamole_expuesto" {
  description = <<-EOT
    Abre el puerto 8080 al exterior: el portal de Guacamole.

    La app movil no implementa VNC. Para "ver el escritorio del alumno" abre el
    portal de Guacamole dentro de una vista web, con la sesion ya iniciada por
    la API, asi que el telefono necesita alcanzar ese puerto directamente.

    A diferencia del 8000, aqui NO hay acceso anonimo: Guacamole exige sesion
    valida. Lo que si viaja en claro es esa sesion.

    TEMPORAL, por el mismo motivo que api_expuesta: en cuanto Nginx Proxy
    Manager publique Guacamole sobre el 443 con TLS, pon esto en false, pon
    guacamole_expuesto en false tambien en group_vars, y en la app cambia la
    direccion a https. No hay que recompilar nada.
  EOT
  type        = bool
  default     = true
}
