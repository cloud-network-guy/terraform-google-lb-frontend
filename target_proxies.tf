locals {
  _target_proxies = local.is_application ? [for i, v in local.url_maps :
    {
      create            = coalesce(v.create, local.create)
      project_id        = local.project_id
      base_name         = local.base_name
      is_application    = local.is_application
      region            = local.region
      is_regional       = local.is_regional
      protocol          = v.protocol
      url_map_index_key = v.index_key
    }
  ] : []
}

locals {
  _target_http_proxies = [for i, v in local._target_proxies :
    merge(v, {
      name = coalesce(var.target_http_proxy_name, "${v.base_name}-http")
    }) if v.protocol == "http"
  ]
  target_http_proxies = [for i, v in local._target_http_proxies :
    merge(v, {
      url_map   = v.is_regional ? google_compute_region_url_map.default[v.url_map_index_key].self_link : google_compute_url_map.default[v.url_map_index_key].self_link
      index_key = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }) if v.create == true
  ]
}

# Global HTTP Target Proxy
resource "google_compute_target_http_proxy" "default" {
  for_each   = { for i, v in local.target_http_proxies : v.index_key => v if v.is_application && !v.is_regional }
  project    = each.value.project_id
  name       = each.value.name
  url_map    = each.value.url_map
  depends_on = [google_compute_url_map.default]
}

# Regional HTTP Target Proxy
resource "google_compute_region_target_http_proxy" "default" {
  for_each   = { for i, v in local.target_http_proxies : v.index_key => v if v.is_application && v.is_regional }
  project    = each.value.project_id
  name       = each.value.name
  url_map    = each.value.url_map
  region     = each.value.region
  depends_on = [google_compute_region_url_map.default]
}

locals {
  _target_https_proxies = [for i, v in local._target_proxies :
    merge(v, {
      name = coalesce(var.target_https_proxy_name, "${v.base_name}-https")
    }) if v.protocol == "https"
  ]
  __target_https_proxies = [for i, v in local._target_https_proxies :
    merge(v, {
      quic_override = upper(trimspace(coalesce(var.quic_override, "NONE")))
      ssl_policy = coalesce(
        var.existing_ssl_policy,
        v.is_regional ?one([for _ in local.ssl_policies : "${local.url_prefix}/${_.project_id}/regions/${local.region}/sslPolicies/${_.name}"]) : null,
        !v.is_regional ? one([for _ in local.ssl_policies : "${local.url_prefix}/${_.project_id}/global/sslPolicies/${_.name}"]) : null,
      )
      ssl_certificates = concat(
        local.existing_ssl_certs,
        [for _ in local.ssl_certs: "${local.url_prefix}/${_.project_id}/${local.is_regional ? "regions/" : ""}${local.region}/sslCertificates/${_.name}"]
      )
    })
  ]
  target_https_proxies = [for i, v in local.__target_https_proxies :
    merge(v, {
      ssl_policy = startswith(v.ssl_policy, local.url_prefix) ? v.ssl_policy : "${local.url_prefix}/${local.project_id}/${local.is_regional ? "regions/" : ""}${local.region}/sslPolicies/${v.ssl_policy}"
      url_map   = v.is_regional ? google_compute_region_url_map.default[v.url_map_index_key].self_link : google_compute_url_map.default[v.url_map_index_key].self_link
      index_key  = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }) if v.create == true
  ]
}

# Global HTTPS Target Proxy
resource "google_compute_target_https_proxy" "default" {
  for_each         = { for i, v in local.target_https_proxies : v.index_key => v if !v.is_regional }
  project          = each.value.project_id
  name             = each.value.name
  url_map          = each.value.url_map
  ssl_certificates = each.value.ssl_certificates
  ssl_policy       = each.value.ssl_policy
  quic_override    = each.value.quic_override
  depends_on = [
    google_compute_url_map.default,
    google_compute_ssl_certificate.default,
    google_compute_ssl_policy.default,
    null_resource.ssl_certs,
  ]
}

# Regional HTTPS Target Proxy
resource "google_compute_region_target_https_proxy" "default" {
  for_each         = { for i, v in local.target_https_proxies : v.index_key => v if v.is_regional }
  project          = each.value.project_id
  name             = each.value.name
  url_map          = each.value.url_map
  ssl_certificates = each.value.ssl_certificates
  ssl_policy       = each.value.ssl_policy
  region           = each.value.region
  depends_on = [
    google_compute_region_url_map.default,
    google_compute_region_ssl_certificate.default,
    google_compute_region_ssl_policy.default,
    null_resource.ssl_certs,
  ]
}

locals {
  _target_tcp_proxies = !local.is_application ? [for i, v in local._target_proxies :
    merge(v, {
      name            = coalesce(var.target_tcp_proxy_name, v.base_name)
      backend_service = local.default_service
    })
  ] : []
  target_tcp_proxies = [for i, v in local._target_tcp_proxies :
    merge(v, {
      index_key = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }) if v.create == true
  ]
}

# Global TCP Proxy
resource "google_compute_target_tcp_proxy" "default" {
  for_each        = { for i, v in local.target_tcp_proxies : v.index_key => v if !v.is_regional }
  project         = each.value.project_id
  name            = each.value.name
  backend_service = each.value.backend_service
}

# Regional TCP Proxy
resource "google_compute_region_target_tcp_proxy" "default" {
  for_each        = { for i, v in local.target_tcp_proxies : v.index_key => v if v.is_regional }
  project         = each.value.project_id
  name            = each.value.name
  backend_service = each.value.backend_service
  region          = each.value.region
}