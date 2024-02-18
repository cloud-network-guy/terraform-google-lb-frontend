output "forwarding_rules" {
  value = [for i, v in local.forwarding_rules :
    {
      index_key       = v.index_key
      name            = v.name
      region          = v.is_regional ? v.region : "global"
      id              = v.is_regional ? try(google_compute_forwarding_rule.default[v.index_key].id, null) : try(google_compute_global_forwarding_rule.default[v.index_key].id, null)
      self_link       = v.is_regional ? try(google_compute_forwarding_rule.default[v.index_key].self_link, null) : try(google_compute_global_forwarding_rule.default[v.index_key].self_link, null)
      backend_service = v.is_regional ? try(google_compute_forwarding_rule.default[v.index_key].backend_service, null) : try(google_compute_global_forwarding_rule.default[v.index_key].backend_service, null)
    }
  ]
}
output "ip_addresses" {
  value = [for i, v in local.ip_addresses : (v.is_regional ? google_compute_address.default[v.index_key].address :
  google_compute_global_address.default[v.index_key].address)]
  #value = local.http_https_ports
}

output "ssl_certs" {
  value = local.ssl_certs
}