provider "aws" {
  region = var.aws_region

  # Se aplican a todos los recursos que soportan tags. El tag "Name" se define
  # recurso a recurso con el patron demo-ar-<tipo>-1.1.
  default_tags {
    tags = {
      Project   = local.prefix
      Version   = local.suffix
      ManagedBy = "Terraform"
    }
  }
}
