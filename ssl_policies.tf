locals {
  tls_versions = {
    "1"   = "TLS_1_0"
    "1_0" = "TLS_1_0"
    "1.0" = "TLS_1_0"
    "1_1" = "TLS_1_1"
    "1.1" = "TLS_1_1"
    "1_2" = "TLS_1_2"
    "1.2" = "TLS_1_2"
  }
  _ssl_policies = var.ssl_policy != null || var.min_tls_version != null ? [
    {
      create          = coalesce(lookup(var.ssl_policy, "create", null), local.create)
      project_id      = lower(trimspace(coalesce(lookup(var.ssl_policy, "project_id", null), local.project_id)))
      name            = lower(trimspace(coalesce(lookup(var.ssl_policy, "name", null), local.base_name)))
      is_regional     = local.is_regional
      region          = local.region
      description     = lookup(var.ssl_policy, "description", null) != null ? trimspace(var.ssl_policy.description) : null
      tls_profile     = upper(trimspace(coalesce(lookup(var.ssl_policy, "tls_profile", null), "MODERN")))
      min_tls_version = upper(trimspace(coalesce(lookup(var.ssl_policy, "min_tls_version", null), var.min_tls_version, "TLS_1_2")))
      region          = lower(trimspace(coalesce(lookup(var.ssl_policy, "region", null), local.region)))
    }
  ] : []
  ssl_policies = [for i, v in local._ssl_policies :
    merge(v, {
      min_tls_version = startswith(v.min_tls_version, "TLS_") ? v.min_tls_version : lookup(local.tls_versions, v.min_tls_version, "TLS_1_2")
      index_key       = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }) if v.create == true
  ]
}

# Global Custom SSL/TLS Policy
resource "google_compute_ssl_policy" "default" {
  for_each        = { for i, v in local.ssl_policies : v.index_key => v if !v.is_regional }
  project         = each.value.project_id
  name            = each.value.name
  description     = each.value.description
  profile         = each.value.tls_profile
  min_tls_version = each.value.min_tls_version
}

# Regional Custom SSL/TLS Policy
resource "google_compute_region_ssl_policy" "default" {
  for_each        = { for i, v in local.ssl_policies : v.index_key => v if v.is_regional }
  project         = each.value.project_id
  name            = each.value.name
  description     = each.value.description
  profile         = each.value.tls_profile
  min_tls_version = each.value.min_tls_version
  region          = each.value.region
}
