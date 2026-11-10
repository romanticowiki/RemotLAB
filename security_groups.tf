##############################################################################
# Security Group
#
# Replica de SG-aularemota (sg-04d70c98528b02aff).
#
# IMPORTANTE: ninguna regla del original referencia a otro security group; todos
# los UserIdGroupPairs vienen vacios. Son solo CIDRs, asi que no hace falta
# ninguna referencia cruzada entre SGs ni ningun ID literal.
#
# Las reglas se declaran como recursos individuales
# (aws_vpc_security_group_ingress_rule / _egress_rule), el enfoque recomendado en
# el provider AWS v6: cada regla tiene su propio ID en el state, se pueden anadir
# y quitar sin recrear el SG, y no producen los diffs perpetuos de los bloques
# inline. Cada recurso admite un unico CIDR, por eso las reglas que en el original
# cubren IPv4 e IPv6 a la vez se parten en dos.
##############################################################################

resource "aws_security_group" "demo_ar_sg" {
  name   = local.name.sg
  vpc_id = aws_vpc.demo_ar_vpc.id

  # El original incluia un timestamp de creacion en la descripcion; se omite.
  description = "Permitir SSH local y web publica - ${local.prefix}-${local.suffix}"

  tags = {
    Name = local.name.sg
  }

  # Sin create_before_destroy a proposito: el nombre es fijo, y crear el nuevo
  # antes de borrar el viejo daria InvalidGroup.Duplicate.
}

##############################################################################
# Ingress
##############################################################################

# tcp 22 desde la IP de administracion. El original documenta esta regla como
# "Entrance to the VM".
resource "aws_vpc_security_group_ingress_rule" "demo_ar_ssh_admin_v4" {
  security_group_id = aws_security_group.demo_ar_sg.id
  description       = "Entrance to the VM"

  ip_protocol = "tcp"
  from_port   = 22
  to_port     = 22
  cidr_ipv4   = var.admin_cidr
}

resource "aws_vpc_security_group_ingress_rule" "demo_ar_http_v4" {
  security_group_id = aws_security_group.demo_ar_sg.id
  description       = "HTTP publico IPv4"

  ip_protocol = "tcp"
  from_port   = 80
  to_port     = 80
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "demo_ar_http_v6" {
  security_group_id = aws_security_group.demo_ar_sg.id
  description       = "HTTP publico IPv6"

  ip_protocol = "tcp"
  from_port   = 80
  to_port     = 80
  cidr_ipv6   = "::/0"
}

resource "aws_vpc_security_group_ingress_rule" "demo_ar_https_v4" {
  security_group_id = aws_security_group.demo_ar_sg.id
  description       = "HTTPS publico IPv4"

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "demo_ar_https_v6" {
  security_group_id = aws_security_group.demo_ar_sg.id
  description       = "HTTPS publico IPv6"

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv6   = "::/0"
}

# tcp 81 restringido a la IP de administracion, igual que el original.
resource "aws_vpc_security_group_ingress_rule" "demo_ar_port81_admin_v4" {
  security_group_id = aws_security_group.demo_ar_sg.id
  description       = "Puerto 81 solo desde la IP de administracion"

  ip_protocol = "tcp"
  from_port   = 81
  to_port     = 81
  cidr_ipv4   = var.admin_cidr
}

##############################################################################
# Egress
#
# El original permite todo el trafico de salida en IPv4 e IPv6 (IpProtocol "-1").
# Con ip_protocol = "-1" NO se declaran from_port ni to_port: el provider lo
# rechaza porque "todos los protocolos" implica todos los puertos.
##############################################################################

resource "aws_vpc_security_group_egress_rule" "demo_ar_egress_all_v4" {
  security_group_id = aws_security_group.demo_ar_sg.id
  description       = "Todo el trafico de salida IPv4"

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "demo_ar_egress_all_v6" {
  security_group_id = aws_security_group.demo_ar_sg.id
  description       = "Todo el trafico de salida IPv6"

  ip_protocol = "-1"
  cidr_ipv6   = "::/0"
}


##############################################################################
# API de supervision (puerto 8000) - TEMPORAL
#
# La abre para que la app movil pueda leer metricas desde una red movil, donde
# la IP cambia y no se puede restringir por CIDR.
#
# Es de SOLO LECTURA y exige un token Bearer, pero viaja en HTTP plano: quien
# capture el trafico ve el token y podria leer metricas (nunca modificar nada).
#
# PARA CERRARLA: pon api_expuesta = false y publica la API detras de Nginx
# Proxy Manager como /api/ sobre el 443, que ya lleva TLS.
##############################################################################

resource "aws_vpc_security_group_ingress_rule" "demo_ar_api" {
  count = var.api_expuesta ? 1 : 0

  security_group_id = aws_security_group.demo_ar_sg.id
  description       = "API de supervision para la app movil (TEMPORAL, sin TLS)"
  ip_protocol       = "tcp"
  from_port         = 8000
  to_port           = 8000
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "${local.prefix}-api-${local.suffix}" }
}

##############################################################################
# Portal de Guacamole para la app movil
#
# La app abre el escritorio del alumno dentro de una vista web apuntando aqui.
# La API le entrega la URL con la sesion ya iniciada, pero el trafico del
# escritorio va del telefono a este puerto directamente.
#
# Sin sesion valida Guacamole no sirve nada, asi que abrirlo no expone
# escritorios; expone la pantalla de login. Lo que falta es el TLS.
#
# PARA CERRARLA: pon guacamole_expuesto = false aqui y en group_vars, y publica
# Guacamole detras de Nginx Proxy Manager sobre el 443.
##############################################################################

resource "aws_vpc_security_group_ingress_rule" "demo_ar_guacamole" {
  count = var.guacamole_expuesto ? 1 : 0

  security_group_id = aws_security_group.demo_ar_sg.id
  description       = "Portal Guacamole para la app movil (TEMPORAL, sin TLS)"
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "${local.prefix}-guacamole-${local.suffix}" }
}
