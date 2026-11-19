variable "config_path" {
  description = "Path to the normalized config (build/config.json) produced by make config."
  type        = string
}

variable "build_dir" {
  description = "Absolute path of the build directory; the kubeconfig is written here."
  type        = string
  validation {
    condition     = startswith(var.build_dir, "/")
    error_message = "build_dir must be an absolute path."
  }
}
