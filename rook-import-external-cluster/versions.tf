terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "~> 2.32.0" # released - 2024-08-14
    }
  }

  required_version = "<= 1.9.5" # released - 2024-08-20
}