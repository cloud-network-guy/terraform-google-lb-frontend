locals {
  _ip_addresses = [for i, v in local.____forwarding_rules :
    merge(v, {
      name            = coalesce(v.address_name, v.name)
      project_id      = v.project_id
      host_project_id = coalesce(v.host_project_id, v.project_id)
      ip_versions     = v.is_internal || v.is_regional ? ["IPV4"] : concat(v.enable_ipv4 ? ["IPV4"] : [], v.enable_ipv6 ? ["IPV6"] : [])
    })
  ]
  ip_addresses = flatten([for i, v in local._ip_addresses :
    [for ip_version in v.ip_versions :
      {
        project_id    = v.project_id
        address_type  = v.is_internal ? "INTERNAL" : "EXTERNAL"
        name          = v.name
        is_regional   = v.is_regional
        region        = v.is_regional ? v.region : "global"
        network       = "projects/${v.host_project_id}/global/networks/${v.network}"
        subnetwork    = "projects/${v.host_project_id}/regions/${v.region}/subnetworks/${v.subnet}"
        prefix_length = v.is_regional ? 0 : null
        purpose       = v.is_psc ? "GCE_ENDPOINT" : v.is_application && v.is_internal && v.redirect_http_to_https ? "SHARED_LOADBALANCER_VIP" : null
        network_tier  = v.is_psc ? null : v.network_tier
        address       = v.ip_address
        ip_version    = ip_version
        index_key     = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
      } if v.create == true || coalesce(v.preserve_ip, false) == true
    ]
  ])
}

# Work-around for scenarios where PSC Consumer Endpoint IP changes
resource "null_resource" "ip_addresses" {
  for_each = { for i, v in local.ip_addresses : v.index_key => true if v.purpose == "GCE_ENDPOINT" }
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
