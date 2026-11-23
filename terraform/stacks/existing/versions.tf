terraform {
  required_version = ">= 1.9, < 2.0"

  # No providers: this stack creates nothing. It only turns the parameter file
  # and a kubeconfig snapshot into the outputs contract.

  # State path is set per environment by scripts/infra.sh:
  #   -backend-config=path=build/state/<provider>-<name>.tfstate
  backend "local" {}
}
