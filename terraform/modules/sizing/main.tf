# Abstract node sizes → provider SKUs. Same vCPU/memory shape on every cloud
# (x86_64, general purpose), so a pool behaves the same wherever it lands.
locals {
  shapes = {
    small  = { vcpu = 2, memory_gib = 8 }
    medium = { vcpu = 4, memory_gib = 16 }
    large  = { vcpu = 8, memory_gib = 32 }
  }

  catalog = {
    aws = {
      small  = "m7i.large"
      medium = "m7i.xlarge"
      large  = "m7i.2xlarge"
    }
    gcp = {
      small  = "e2-standard-2"
      medium = "e2-standard-4"
      large  = "e2-standard-8"
    }
    azure = {
      small  = "Standard_D2s_v5"
      medium = "Standard_D4s_v5"
      large  = "Standard_D8s_v5"
    }
    # kind nodes are containers sharing the host; size is informational only.
    local = {
      small  = "kind-node"
      medium = "kind-node"
      large  = "kind-node"
    }
  }
}
