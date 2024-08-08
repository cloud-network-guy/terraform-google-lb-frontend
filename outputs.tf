output "forwarding_rules" {
  value = [for i, v in local.forwarding_rules :
    {
      #is_regional  = v.is_regional
      index_key    = v.index_key
      name         = v.name
      region       = v.region
      ip_address   = v.ip_address
      address_key  = v.address_key
      address_name = v.address_name
      id           = local.is_regional ? try(google_compute_forwarding_rule.default[v.index_key].id, null) : try(google_compute_global_forwarding_rule.default[v.index_key].id, null)
      self_link    = local.is_regional ? try(google_compute_forwarding_rule.default[v.index_key].self_link, null) : try(google_compute_global_forwarding_rule.default[v.index_key].self_link, null)
      backend_service = local.is_regional ? try(google_compute_forwarding_rule.default[v.index_key].backend_service, null) : try(google_compute_global_forwarding_rule.default[v.index_key].backend_service,
      null)
      connected_endpoints = local.is_regional ? try(google_compute_forwarding_rule.default[v.index_key].connected_endpoints, null) : null
    }
  ]
}
output "ip_addresses" {
  value = [for i, v in local.ip_addresses :

    {
      name    = local.is_regional ? google_compute_address.default[v.index_key].name : google_compute_global_address.default[v.index_key].name,
      address = local.is_regional ? google_compute_address.default[v.index_key].address : google_compute_global_address.default[v.index_key].address,
    }
  ]
}
output "ipv4_address" {
  value = one([for i, v in local.ip_addresses :
    (local.is_regional ? google_compute_address.default[v.index_key].address : google_compute_global_address.default[v.index_key].address) if v.ip_version == "IPV4"
  ])
}
output "ipv6_address" {
  value = one([for i, v in local.ip_addresses :
    (local.is_regional ? google_compute_address.default[v.index_key].address : google_compute_global_address.default[v.index_key].address) if v.ip_version == "IPV6"
  ])
}
output "ssl_certs" {
  value = local.ssl_certs
}

output "debug" {
  value = {
    forwarding_rules = local.forwarding_rules
    ssl_certs        = local.ssl_certs
  }
}