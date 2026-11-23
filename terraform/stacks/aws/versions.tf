terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.72.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9.1"
    }
    # Required by the EKS module; pinned here so the lock file covers them.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.4.2"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14.2"
    }
  }

  # golden-k8 never applies cloud stacks (validated and mock-tested only).
  # To provision for real, replace this with a remote backend (S3).
  backend "local" {}
}
