##############################################################################
# Route 53: DESACTIVADO
#
# Este despliegue puede usar un proveedor de DNS externo, no Route 53.
#
# El codigo original hacia un data "aws_route53_zone" sobre una hosted zone
# que vive en OTRA cuenta de AWS. Un data source falla en "terraform plan" si
# no encuentra el recurso, asi que bastaba su presencia para bloquear todo el
# despliegue en una cuenta nueva.
#
# El nombre publico ahora es informativo: se declara en la variable lab_fqdn
# y el registro DNS lo mantiene No-IP apuntando a la Elastic IP. Hay que
# actualizarlo A MANO en el panel de No-IP despues del primer apply, con el
# valor que imprime el output "eip_public_ip".
#
# Para volver a Route 53: recupera este fichero del historial de git
#   git show HEAD:route53.tf > route53.tf
# y devuelve las variables domain_name / hostname / create_aaaa_record a
# variables.tf.
##############################################################################
