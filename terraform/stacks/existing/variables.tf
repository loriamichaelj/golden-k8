variable "config_path" {
  description = "Path to the normalized config (build/config.json) produced by make config."
  type        = string
}

variable "build_dir" {
  description = "Absolute path of the build directory; the kubeconfig snapshot lives here."
  type        = string
  validation {
    condition     = startswith(var.build_dir, "/")
    error_message = "build_dir must be an absolute path."
  }
}

variable "kubeconfig_path" {
  description = "Kubeconfig holding only the target context (scripts/infra.sh writes it). Defaults to <build_dir>/kubeconfig-golden-<name>."
  type        = string
  default     = null
}
