locals {
  _target_proxies = [for i, v in var.target_proxies :
    {
      create          = coalesce(v.create, true)
      project_id      = coalesce(v.project_id, var.project_id)
      name            = coalesce(v.name, "ssl-policy-${i}")
      is_regional     = var.region != null ? true : false
      backend_service = null
      url_map         = null
      uic_override    = coalesce(v.quic_override, "NONE")
      ssl_policy      = null
    }
  ]
  target_proxies = [for i, v in var.target_proxies :
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
  count   = local.create && local.is_global && local.is_http && local.enable_http ? 1 : 0
  project = var.project_id
  name    = "${local.name_prefix}-http"
  url_map = one(google_compute_url_map.http).id
}

# Regional HTTP Target Proxy
resource "google_compute_region_target_http_proxy" "default" {
  count   = local.create && local.is_regional && local.is_http && local.enable_http ? 1 : 0
  project = var.project_id
  name    = "${local.name_prefix}-http"
  url_map = one(google_compute_region_url_map.http).id
  region  = local.region
}

# Global HTTPS Target Proxy
resource "google_compute_target_https_proxy" "default" {
  count   = local.create && local.is_global && local.is_http && local.enable_https ? 1 : 0
  project = var.project_id
  name    = "${local.name_prefix}-https"
  url_map = one(google_compute_url_map.https).id
  ssl_certificates = local.use_ssc ? [google_compute_ssl_certificate.default["self-signed"].name] : coalescelist(
    local.ssl_cert_names,
    [for i, v in local.certs_to_upload : google_compute_ssl_certificate.default[v.name].id]
  )
  ssl_policy    = local.ssl_policy
  quic_override = local.quic_override
  depends_on    = [google_compute_url_map.https, google_compute_ssl_certificate.default]
}

# Regional HTTPS Target Proxy
resource "google_compute_region_target_https_proxy" "default" {
  count   = local.create && local.is_regional && local.is_http && local.enable_https ? 1 : 0
  project = var.project_id
  name    = "${local.name_prefix}-https"
  url_map = one(google_compute_region_url_map.https).id
  ssl_certificates = local.use_ssc ? [google_compute_region_ssl_certificate.default["self-signed"].name] : coalescelist(
    local.ssl_cert_names,
    [for i, v in local.certs_to_upload : google_compute_region_ssl_certificate.default[v.name].id]
  )
  #ssl_policy       = local.ssl_policy
  #quic_override = local.quic_override
  region     = local.region
  depends_on = [google_compute_region_url_map.https, google_compute_region_ssl_certificate.default]
}
