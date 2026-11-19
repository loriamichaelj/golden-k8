output "contract" {
  description = "Outputs contract (see modules/contract)."
  value       = module.contract.contract
}

output "app_url" {
  description = "Where the sample app will be reachable once deployed."
  value       = "http://${local.spec.app.expose.host}${local.host_http_port == 80 ? "" : ":${local.host_http_port}"}"
}
