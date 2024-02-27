locals {
  _target_proxies = [for i, v in local.url_maps :
    {
      create                 = coalesce(local.create, true)
      project_id             = local.project_id
      name                   = coalesce(var.target_proxy_name, var.name, local.name_prefix)
      is_regional            = local.is_regional
      region                 = local.region
      is_application         = local.is_application
      backend_service        = !local.is_application ? local.default_service : null
      url_map                = local.is_regional ? "projects/${v.project_id}/regions/${v.region}/urlMaps/${v.name}" : "projects/${v.project_id}/global/urlMaps/${v.name}"
      quic_override          = upper(trimspace(coalesce(var.quic_override, "NONE")))
      ssl_certificates       = local.is_application ? coalescelist(local.ssl_certificates, [local.ssl_certs[0].name]) : null
      ssl_policy             = var.ssl_policy
      redirect_http_to_https = local.redirect_http_to_https
      url_map_index_key      = v.index_key
    }
  ]
  target_proxies = [for i, v in local._target_proxies :
    merge(v, {
      # Certs technically should be referenced by full URL
      #ssl_certificates = [for ssl_cert in v.ssl_certificates :
      #  startswith(ssl_cert, local.url_prefix) ? ssl_cert : "${local.url_prefix}/${v.project_id}/${v.is_regional ? "regions/${v.region}" : "global"}/sslCertificates/${ssl_cert}"
      #]
      ssl_policy = startswith(ssl_cert, local.url_prefix) ? ssl_policy : "${local.url_prefix}/${v.project_id}/${v.is_regional ? "regions/${v.region}" : "global"}/sslPolicies/${ssl_policy}"
      index_key = local.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
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
  for_each   = { for i, v in local.target_proxies : v.index_key => v if v.is_application && v.redirect_http_to_https && !v.is_regional }
  project    = each.value.project_id
  name       = "${each.value.name}-http"
  url_map    = google_compute_url_map.http-to-https[each.value.url_map_index_key].self_link
  depends_on = [google_compute_url_map.http-to-https]
}

# Regional HTTP Target Proxy
resource "google_compute_region_target_http_proxy" "default" {
  for_each   = { for i, v in local.target_proxies : v.index_key => v if v.is_application && v.redirect_http_to_https && v.is_regional }
  project    = each.value.project_id
  name       = "${each.value.name}-http"
  url_map    = google_compute_region_url_map.http-to-https[each.value.url_map_index_key].self_link
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
  depends_on = [
    google_compute_url_map.https,
    google_compute_ssl_certificate.default,
    google_compute_ssl_policy.default,
    null_resource.ssl_certs,
  ]
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
  depends_on = [
    google_compute_region_url_map.https,
    google_compute_region_ssl_certificate.default,
    google_compute_region_ssl_policy.default,
    null_resource.ssl_certs,
  ]
}
