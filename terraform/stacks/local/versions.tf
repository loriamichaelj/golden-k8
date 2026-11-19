terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.13.0"
    }
  }

  # State path is set per environment by scripts/infra.sh:
  #   -backend-config=path=build/state/<provider>-<name>.tfstate
  backend "local" {}
}
