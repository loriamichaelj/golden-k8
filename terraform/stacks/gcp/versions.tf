terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.10.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9.1"
    }
  }

  # golden-k8 never applies cloud stacks (validated and mock-tested only).
  # To provision for real, replace this with a remote backend (GCS).
  backend "local" {}
}
