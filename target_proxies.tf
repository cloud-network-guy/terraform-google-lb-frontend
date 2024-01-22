locals {
  _target_proxies = [for i, v in local.url_maps :
    {
      create          = coalesce(v.create, true)
      project_id      = coalesce(v.project_id, var.project_id)
      name            = coalesce(v.name, "target-proxy-${i}")
      is_regional     = var.region != null ? true : false
      backend_service = null
      url_map         = null
      uic_override    = coalesce(v.quic_override, "NONE")
      ssl_policy      = null
    }
  ]
  target_proxies = [for i, v in local._target_proxies :
    {
      index_key = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    } if v.create == true
  ]
}

# Global TCP Proxy
resource "google_compute_target_tcp_proxy" "default" {
  for_each        = { for i, v in local.target_proxies : v.index_key => v if !v.is_regional }
  project         = each.value.project_id
  name            = each.value.name
  backend_service = each.value.backend_service
}

# Regional TCP Proxy
resource "google_compute_region_target_tcp_proxy" "default" {
  for_each        = { for i, v in local.target_proxies : v.index_key => v if v.is_regional }
  project         = each.value.project_id
  name            = each.value.name
  backend_service = each.value.backend_service
  region          = each.value.region
}

# Global HTTP Target Proxy
resource "google_compute_target_http_proxy" "default" {
  for_each = { for i, v in local.target_proxies : v.index_key => v if !v.is_regional }
  project  = each.value.project_id
  name     = each.value.name
  url_map  = each.value.url_map
}

# Regional HTTP Target Proxy
resource "google_compute_region_target_http_proxy" "default" {
  for_each = { for i, v in local.target_proxies : v.index_key => v if v.is_regional }
  project  = each.value.project_id
  name     = each.value.name
  url_map  = each.value.url_map
  region   = each.value.region
}

# Global HTTPS Target Proxy
resource "google_compute_target_https_proxy" "default" {
  for_each         = { for i, v in local.target_proxies : v.index_key => v if !v.is_regional }
  project          = each.value.project_id
  name             = each.value.name
  url_map          = each.value.url_map
  ssl_certificates = each.value.ssl_certificates
  ssl_policy       = each.value.ssl_policy
  quic_override    = each.value.quic_override
  #depends_on       = [google_compute_url_map.https, google_compute_ssl_certificate.default]
}

# Regional HTTPS Target Proxy
resource "google_compute_region_target_https_proxy" "default" {
  for_each         = { for i, v in local.target_proxies : v.index_key => v if v.is_regional }
  project          = each.value.project_id
  name             = each.value.name
  url_map          = each.value.url_map
  ssl_certificates = each.value.ssl_certificates
  ssl_policy       = each.value.ssl_policy
  #quic_override    = each.value.quic_override
  region = each.value.region
  #depends_on       = [google_compute_region_url_map.https, google_compute_region_ssl_certificate.default]
}
