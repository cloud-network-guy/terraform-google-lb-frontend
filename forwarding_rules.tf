locals {
  _forwarding_rules = [
    {
      create                 = coalesce(local.create, true)
      project_id             = local.project_id
      host_project_id        = local.host_project_id
      name                   = coalesce(var.forwarding_rule_name, local.base_name)
      type = local.type
      is_internal            = local.is_internal
      is_psc                 = local.is_psc
      is_regional            = local.is_regional
      region                 = local.region
      is_application         = local.is_application
      ports                  = local.ports
      all_ports              = local.is_psc || length(local.ports) > 0 ? false : local.all_ports
      network                = local.network
      subnet                 = local.subnet
      network_tier           = local.is_psc ? null : local.network_tier
      labels                 = length(local.labels) > 0 ? local.labels : null
      ip_address             = local.ip_address
      address_name           = local.ip_address_name
      enable_ipv4            = local.enable_ipv4
      enable_ipv6            = local.enable_ipv6
      preserve_ip            = local.preserve_ip
      is_mirroring_collector = false # TODO
      is_classic             = local.is_classic
      ip_protocol            = local.is_psc || local.ip_protocol == "HTTP" ? null : local.ip_protocol
      allow_global_access    = local.is_internal && !local.is_psc ? local.allow_global_access : null
      load_balancing_scheme  = local.load_balancing_scheme
      http_https_ports       = local.is_application ? concat(local.enable_http || local.redirect_http_to_https ? [local.http_port] : [], local.enable_https ? [local.https_port] : []) : []
      backend_service        = local.is_application ? null : local.default_service
      psc                    = var.psc
      source_ip_ranges       = [] # TODO
      target                 = "blah"
    }
  ]
  __forwarding_rules = flatten([for i, v in local._forwarding_rules :
    [for ip_port in setproduct(local.ip_versions, v.is_application ? v.http_https_ports : [0]) :
      merge(v, {
        port_range = v.is_application ? ip_port[1] : null
        name       = v.is_application ? "${v.name}${local.enable_ipv6 ? "-${lower(ip_port[0])}" : ""}-${lookup(local.port_names, ip_port[1], "error")}" : v.name
        #address_key = v.is_regional ? "${v.project_id}/${v.region}/${v.address_name}" : "${v.project_id}/${v.address_name}"
        address_key = one([for _ in local.ip_addresses : _.index_key if _.forwarding_rule_name == v.name && _.region == v.region && _.ip_version == upper(ip_port[0])])
        target      = startswith(v.target, local.url_prefix) ? v.target : "${local.url_prefix}/${v.project_id}/${local.is_regional ? "regions/" : ""}${local.region}/targetHttp${(ip_port[1] != 80 ? "s" : "")}Proxies/${v.name}-${lookup(local.port_names, ip_port[1], "error")}"
        ip_version  = ip_port[0]
      })
    ]
  ])
  ___forwarding_rules = [for i, v in local.__forwarding_rules :
    merge(v, {
      ip_address = try(coalesce(
        #v.ip_version == "IPV4" ? coalesce(v.ipv4_address_name, v.ip_address_name) : null,
        #v.ip_version == "IPV6" ? coalesce(v.ipv6_address_name, v.ip_address_name) : null,
        v.is_psc ? google_compute_address.default["${v.project_id}/${v.region}/${v.address_name}"].self_link : null,
        v.ip_address,
        v.is_regional ? google_compute_address.default[v.address_key].address : null,
        !v.is_regional ? google_compute_global_address.default[v.address_key].address : null,
      ), null) # null address will allocate & use emphem IP
      target = v.is_application ? v.target : null
    })
  ]
  forwarding_rules = [for i, v in local.___forwarding_rules :
    merge(v, {
      target                = v.is_psc ? "${local.url_prefix}/${v.target_project_id}/${local.is_regional ? "regions/" : ""}${local.region}/serviceAttachments/${v.target}" : v.target
      load_balancing_scheme = v.is_psc ? "" : v.load_balancing_scheme # null doesn't work with PSC forwarding rules
      subnetwork            = v.is_psc ? null : v.is_internal ? local.subnet : null
      index_key             = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }) if v.create == true
  ]
}

# Regional Forwarding rule
resource "google_compute_forwarding_rule" "default" {
  for_each               = { for i, v in local.forwarding_rules : v.index_key => v if v.is_regional }
  project                = each.value.project_id
  name                   = each.value.name
  port_range             = each.value.port_range
  ports                  = each.value.ports
  all_ports              = each.value.all_ports
  backend_service        = each.value.backend_service
  target                 = each.value.target
  ip_address             = each.value.ip_address
  load_balancing_scheme  = each.value.load_balancing_scheme
  ip_protocol            = each.value.ip_protocol
  labels                 = each.value.labels
  is_mirroring_collector = each.value.is_mirroring_collector
  network                = each.value.network
  region                 = each.value.region
  subnetwork             = each.value.subnetwork
  network_tier           = each.value.network_tier
  allow_global_access    = each.value.allow_global_access
  source_ip_ranges       = each.value.source_ip_ranges
  depends_on = [
    google_compute_address.default,
    google_compute_region_target_tcp_proxy.default,
    google_compute_region_target_http_proxy.default,
    google_compute_region_target_https_proxy.default,
  ]
}

# Global Forwarding rule
resource "google_compute_global_forwarding_rule" "default" {
  for_each              = { for i, v in local.forwarding_rules : v.index_key => v if !v.is_regional }
  project               = each.value.project_id
  name                  = each.value.name
  port_range            = each.value.port_range
  target                = each.value.target
  ip_address            = each.value.ip_address
  load_balancing_scheme = each.value.load_balancing_scheme
  ip_protocol           = each.value.ip_protocol
  labels                = each.value.labels
  source_ip_ranges      = each.value.source_ip_ranges
  depends_on = [
    google_compute_global_address.default,
    google_compute_target_tcp_proxy.default,
    google_compute_target_http_proxy.default,
    google_compute_target_https_proxy.default,
  ]
}
