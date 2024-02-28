locals {
  _ip_addresses = [for i, v in local._forwarding_rules :
    {
      create               = coalesce(local.create, true)
      project_id           = v.project_id
      host_project_id      = coalesce(v.host_project_id, v.project_id)
      forwarding_rule_name = v.name
      address_type         = local.type
      address              = v.ip_address
      name                 = local.ip_address_name
      is_psc               = v.is_psc
      is_regional     = local.region != "global" ? true : false
            region                 = local.is_regional ? local.region : null
      is_internal = local.is_internal
      network              = "projects/${local.host_project_id}/global/networks/${v.network}"
      subnetwork           = v.is_regional && v.is_internal ? "projects/${local.host_project_id}/regions/${v.region}/subnetworks/${v.subnet}" : null
      purpose              = local.is_psc ? "GCE_ENDPOINT" : local.is_application && local.is_internal && local.redirect_http_to_https ? "SHARED_LOADBALANCER_VIP" : null
      network_tier         = local.is_psc ? null : local.network_tier
      ip_versions          = local.ip_versions
    }
  ]
  __ip_addresses = flatten([for i, v in local._ip_addresses :
    [for ip_version in v.ip_versions :
      merge(v, {
        name       = v.is_internal ? v.name : "${v.name}-${lower(ip_version)}"
        ip_version = ip_version
      })
    ]
  ])
  ip_addresses = [for i, v in local.__ip_addresses :
    merge(v, {
      prefix_length = v.is_regional ? 0 : null
      index_key     = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }) if v.create == true
  ]
}

# Work-around for scenarios where PSC Consumer Endpoint IP changes
resource "null_resource" "ip_addresses" {
  for_each = { for i, v in local.ip_addresses : v.index_key => true if v.is_psc }
}

# Regional static IP
resource "google_compute_address" "default" {
  for_each      = { for i, v in local.ip_addresses : v.index_key => v if v.is_regional }
  project       = each.value.project_id
  name          = each.value.name
  address_type  = each.value.address_type
  ip_version    = each.value.ip_version
  address       = each.value.address
  region        = each.value.region
  subnetwork    = each.value.subnetwork
  network_tier  = each.value.network_tier
  purpose       = each.value.purpose
  prefix_length = each.value.prefix_length
  depends_on    = [null_resource.ip_addresses]
}

# Global static IP
resource "google_compute_global_address" "default" {
  for_each     = { for i, v in local.ip_addresses : v.index_key => v if !v.is_regional }
  project      = each.value.project_id
  name         = each.value.name
  address_type = each.value.address_type
  ip_version   = each.value.ip_version
  address      = each.value.address
}
