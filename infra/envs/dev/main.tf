terraform {
  required_version = ">= 1.6.0"
  required_providers {
    terraform = {
      source  = "hashicorp/terraform"
      version = "~> 1.0"
    }
  }
}

resource "terraform_data" "marker" {
  input = "env=dev"
}
