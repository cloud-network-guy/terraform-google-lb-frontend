locals {
  _ssl_policies = [for i, v in var.ssl_policies :
    {
      create          = coalesce(v.create, true)
      project_id      = coalesce(v.project_id, var.project_id)
      name            = coalesce(v.name, "ssl-policy-${i}")
      is_regional     = var.region != null ? true : false
      region          = var.region
      min_tls_version = coalesce(v.min_tls_version, "TLS_1_2") # I never did like Poodles
      tls_profile     = coalesce(v.tls_profile, "MODERN")
    }
  ]
  ssl_policies = [for i, v in var.ssl_policies :
    {
      index_key = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }
  ]
}

# Global Custom SSL/TLS Policy
resource "google_compute_ssl_policy" "default" {
  for_each        = { for i, v in local.ssl_policies : v.index_key => v if !v.is_regional }
  project         = each.value.project_id
  name            = each.value.name
  profile         = each.value.tls_profile
  min_tls_version = each.value.min_tls_version
  address_type    = each.value.address_type
}

# Regional Custom SSL/TLS Policy
resource "google_compute_region_ssl_policy" "default" {
  for_each        = { for i, v in local.ssl_policies : v.index_key => v if v.is_regional }
  project         = each.value.project_id
  name            = each.value.name
  profile         = each.value.tls_profile
  min_tls_version = each.value.min_tls_version
  region          = each.value.region
}
