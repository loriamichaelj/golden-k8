variable "config_path" {
  description = "Path to the normalized config (build/config.json) produced by make config."
  type        = string
  validation {
    condition     = try(jsondecode(file(var.config_path)).spec.provider, "") == "azure"
    error_message = "stacks/azure only handles provider azure: ${var.config_path} is missing or names another provider."
  }
}

variable "build_dir" {
  description = "Absolute path of the build directory; the kubeconfig is written here."
  type        = string
  validation {
    condition     = startswith(var.build_dir, "/")
    error_message = "build_dir must be an absolute path."
  }
}
