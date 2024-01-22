
locals {
  _forwarding_rules = [for i, v in var.lb_frontends :
    {
      create                 = coalesce(v.create, true)
      project_id             = coalesce(v.project_id, var.project_id)
      host_project_id        = try(coalesce(v.host_project_id, var.host_project_id), null)
      name                   = coalesce(v.name, "${var.name_prefix}-${i}")
      description            = coalesce(v.description, "Managed by Terraform")
      region                 = try(coalesce(v.region, var.region), null)
      ports                  = coalesce(v.ports, [])
      all_ports              = coalesce(v.all_ports, false)
      network                = coalesce(v.network, var.network, "default")
      subnet                 = v.subnet
      labels                 = { for k, v in coalesce(v.labels, {}) : k => lower(replace(v, " ", "_")) }
      ip_address             = v.ip_address
      address_name           = v.ip_address_name
      enable_ipv4            = coalesce(v.enable_ipv4, true)
      enable_ipv6            = coalesce(v.enable_ipv6, false)
      preserve_ip            = coalesce(v.preserve_ip, false)
      is_managed             = false # TODO
      is_mirroring_collector = false # TODO
      allow_global_access    = coalesce(v.allow_global_access, false)
      backend_service        = try(coalesce(v.backend_service_id, v.backend_service, v.backend_service_name), null)
      target                 = try(coalesce(v.target_id, v.target, v.target_name), null)
      target_region          = v.target_region
      target_project_id      = v.target_project_id
      psc                    = v.psc
    } if v.create == true || coalesce(v.preserve_ip, false) == true
  ]
  __forwarding_rules = [for i, v in local._forwarding_rules :
    merge(v, {
      is_regional   = try(coalesce(v.region, v.target_region, v.subnet), null) != null ? true : false
      is_internal   = lookup(v, "subnet", null) != null ? true : false
      ip_protocol   = length(v.ports) > 0 || v.all_ports ? "TCP" : "HTTP"
      is_psc        = lookup(v, "target_id", null) != null || v.target != null ? true : false
      target        = v.backend_service == null ? v.target : null
      target_region = try(coalesce(v.target_region, v.region != null ? v.region : null), null)
    })
  ]
  ___forwarding_rules = [for i, v in local.__forwarding_rules :
    merge(v, {
      network_tier = v.is_managed && !v.is_internal ? "STANDARD" : null
      subnetwork   = v.subnet
      ip_protocol  = v.is_psc ? null : v.ip_protocol
      all_ports    = v.is_psc || length(v.ports) > 0 ? false : v.all_ports
      port_range   = v.is_managed ? v.port_range : null
      #target       = v.is_regional ? (contains(["TCP", "SSL"], v.ip_protocol) ? (v.is_psc ? v.target : null) : null) : null
      target = v.target != null ? (startswith(v.target, "projects/") ? v.target : (
        "projects/${v.target_project_id}/${(v.is_regional ? "regions/${v.target_region}" : "global")}/serviceAttachments/${v.target}"
      )) : null
      backend_service = v.backend_service != null ? (startswith(v.backend_service, "projects/") ? v.backend_service : (
        "projects/${v.project_id}/${(v.is_regional ? "regions/${v.region}" : "global")}/backendServices/${v.backend_service}"
      )) : null
    })
  ]
  ____forwarding_rules = [for i, v in local.___forwarding_rules :
    merge(v, {
      region                = v.is_regional ? coalesce(v.region, v.target_region) : null
      load_balancing_scheme = v.is_managed ? v.is_internal ? "INTERNAL_MANAGED" : (v.is_classic ? "EXTERNAL" : "EXTERNAL_MANAGED") : (v.is_internal ? "INTERNAL" : "EXTERNAL")
      allow_global_access   = v.is_internal && !v.is_psc ? v.allow_global_access : null
    })
  ]
  forwarding_rules = [
    for i, v in local.____forwarding_rules :
    merge(v, {
      ip_address            = v.is_psc ? google_compute_address.default["${v.project_id}/${v.region}/${v.address_name}"].self_link : v.ip_address
      load_balancing_scheme = v.is_psc ? "" : v.load_balancing_scheme
      index_key             = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    })
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
  subnetwork             = each.value.is_psc ? null : each.value.subnetwork
  network_tier           = each.value.network_tier
  allow_global_access    = each.value.allow_global_access
  depends_on             = [null_resource.ip_addresses]
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
  depends_on            = [google_compute_global_address.default]
}
