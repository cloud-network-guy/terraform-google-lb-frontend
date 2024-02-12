locals {
  _target_proxies = [for i, v in local.url_maps :
    {
      create           = coalesce(v.create, true)
      project_id       = coalesce(v.project_id, var.project_id)
      name             = coalesce(v.name, "target-proxy-${i}")
      is_regional      = v.is_regional
      region           = v.region
      is_application   = v.is_application
      backend_service  = !v.is_application ? v.default_service : null
      url_map          = v.is_regional ? "projects/${v.project_id}/regions/${v.region}/urlMaps/${v.name}" : "projects/${v.project_id}/global/urlMaps/${v.name}"
      quic_override    = upper(trimspace(coalesce(v.quic_override, "NONE")))
      ssl_certificates = coalesce(v.ssl_certs, [])
      ssl_policy       = v.ssl_policy
    }
  ]
  target_proxies = [for i, v in local._target_proxies :
    merge(v, {
      # If no SSL certs provided, use the first one
      ssl_certificates = !v.is_application ? null : coalescelist(concat(
        v.is_regional ? [google_compute_region_ssl_certificate.default["otc-ems-bcc1/northamerica-northeast1/prod"].self_link] : [],
        !v.is_regional ? [values(google_compute_ssl_certificate.default)[0].id] : [],
      ))
      index_key = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }) if v.create == true
  ]
}

# Global TCP Proxy
resource "google_compute_target_tcp_proxy" "default" {
  for_each        = { for i, v in local.target_proxies : v.index_key => v if !v.is_application && !v.is_regional }
  project         = each.value.project_id
  name            = each.value.name
  backend_service = each.value.backend_service
}

# Regional TCP Proxy
resource "google_compute_region_target_tcp_proxy" "default" {
  for_each        = { for i, v in local.target_proxies : v.index_key => v if !v.is_application && v.is_regional }
  project         = each.value.project_id
  name            = each.value.name
  backend_service = each.value.backend_service
  region          = each.value.region
}

# Global HTTP Target Proxy
resource "google_compute_target_http_proxy" "default" {
  for_each   = { for i, v in local.target_proxies : v.index_key => v if v.is_application && !v.is_regional }
  project    = each.value.project_id
  name       = "${each.value.name}-http"
  url_map    = "${each.value.url_map}-http"
  depends_on = [google_compute_url_map.http-to-https]
}

# Regional HTTP Target Proxy
resource "google_compute_region_target_http_proxy" "default" {
  for_each   = { for i, v in local.target_proxies : v.index_key => v if v.is_application && v.is_regional }
  project    = each.value.project_id
  name       = "${each.value.name}-http"
  url_map    = "${each.value.url_map}-http"
  region     = each.value.region
  depends_on = [google_compute_region_url_map.http-to-https]
}

# Global HTTPS Target Proxy
resource "google_compute_target_https_proxy" "default" {
  for_each         = { for i, v in local.target_proxies : v.index_key => v if v.is_application && !v.is_regional }
  project          = each.value.project_id
  name             = "${each.value.name}-https"
  url_map          = "${each.value.url_map}-https"
  ssl_certificates = each.value.ssl_certificates
  ssl_policy       = each.value.ssl_policy
  quic_override    = each.value.quic_override
  depends_on       = [google_compute_url_map.https, google_compute_ssl_certificate.default]
}

# Regional HTTPS Target Proxy
resource "google_compute_region_target_https_proxy" "default" {
  for_each         = { for i, v in local.target_proxies : v.index_key => v if v.is_application && v.is_regional }
  project          = each.value.project_id
  name             = "${each.value.name}-https"
  url_map          = "${each.value.url_map}-https"
  ssl_certificates = each.value.ssl_certificates
  ssl_policy       = each.value.ssl_policy
  region           = each.value.region
  depends_on       = [google_compute_region_url_map.https, google_compute_region_ssl_certificate.default]
}
