terraform {
  required_version = ">= 1.5"

  # Estado LOCAL a proposito (terraform.tfstate en esta carpeta).
  #
  # El backend S3 original apuntaba a un bucket de otra cuenta AWS, asi que
  # terraform init fallaba antes de empezar. Para volver a estado remoto:
  # crea tu bucket, descomenta este bloque con TU nombre y lanza
  # "terraform init -migrate-state".
  #
  # backend "s3" {
  #   bucket       = "TU-BUCKET-DE-ESTADO"
  #   key          = "aula-remota/terraform.tfstate"
  #   region       = "us-east-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
