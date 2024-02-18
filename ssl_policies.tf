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
  _ssl_policies = [for i, v in var.ssl_policies :
    {
      create          = coalesce(v.create, local.create, true)
      project_id      = coalesce(v.project_id, local.project_id)
      name            = lower(trimspace(coalesce(v.name, "ssl-policy-${i}")))
      description     = v.description
      is_regional     = v.region != null ? true : local.is_regional
      region          = try(coalesce(v.region, local.region), null)
      tls_profile     = upper(trimspace(coalesce(v.tls_profile, "MODERN")))
      min_tls_version = v.min_tls_version != null ? lookup(local.tls_versions, v.min_tls_version, null) : null
    }
  ]
  ssl_policies = [for i, v in local._ssl_policies :
    merge(v, {
      min_tls_version = coalesce(v.min_tls_version, upper(trimspace(coalesce(var.min_tls_version, "TLS_1_2"))))
      index_key       = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    })
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
