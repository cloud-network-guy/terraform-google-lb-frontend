locals {
  _url_maps = [for frontend in local.forwarding_rules :
    {
      create          = coalesce(frontend.create, true)
      project_id      = frontend.project_id
      name            = frontend.name
      is_regional     = frontend.is_regional
      region          = frontend.region
      is_application  = frontend.is_application
      default_service = frontend.default_service
      routing_rules = [for i, v in coalesce(frontend.routing_rules, []) :
        {
          name       = coalesce(frontend.name, "path-matcher-${i + 1}")
          hosts      = [for host in v.hosts : length(split(".", host)) > 1 ? host : "${host}.${v.domains[0]}"]
          path_rules = coalesce(v.path_rules, [])
        }
      ]
      redirect_http_to_https = coalesce(frontend.redirect_http_to_https, false)
      quic_override          = frontend.quic_override
      ssl_certs              = frontend.ssl_certs
      ssl_policy             = frontend.ssl_policy
    } if frontend.is_application == true
  ]
  url_maps = [for i, v in local._url_maps :
    merge(v, {
      index_key = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }) if v.create == true
  ]
}

# Global URL Map for HTTP -> HTTPS redirect
resource "google_compute_url_map" "http-to-https" {
  for_each        = { for i, v in local.url_maps : v.index_key => v if v.redirect_http_to_https && !v.is_regional }
  project         = each.value.project_id
  name            = "${each.value.name}-http"
  default_service = null
  default_url_redirect {
    https_redirect = true
    strip_query    = false
  }
}

# Regional URL Map for HTTP -> HTTPS redirect
resource "google_compute_region_url_map" "http-to-https" {
  for_each        = { for i, v in local.url_maps : v.index_key => v if v.redirect_http_to_https && v.is_regional }
  project         = each.value.project_id
  name            = "${each.value.name}-http"
  default_service = null
  default_url_redirect {
    https_redirect = true
    strip_query    = false
  }
  region = each.value.region
}

# Global HTTPS URL MAP
resource "google_compute_url_map" "https" {
  for_each        = { for i, v in local.url_maps : v.index_key => v if !v.is_regional }
  project         = each.value.project_id
  name            = "${each.value.name}-https"
  default_service = each.value.default_service
  dynamic "host_rule" {
    for_each = each.value.host_rule
    content {
      path_matcher = host_rule.value.patch_matcher
      hosts        = host_rule.value.hosts
    }
  }
  dynamic "path_matcher" {
    for_each = each.value.routing_rules
    content {
      name            = path_matcher.value.name
      default_service = lookup(local.backend_ids, coalesce(path_matcher.value.backend, path_matcher.key), null)
      dynamic "route_rules" {
        for_each = path_matcher.value.request_headers_to_remove != null ? [true] : []
        content {
          priority = coalesce(path_matcher.value.priority, 1)
          service  = lookup(local.backend_ids, coalesce(path_matcher.value.backend, path_matcher.key), null)
          match_rules {
            prefix_match = each.value.prefix_match
          }
          header_action {
            request_headers_to_remove = path_matcher.value.request_headers_to_remove
          }
        }
      }
      dynamic "path_rule" {
        for_each = path_matcher.value.path_rules
        content {
          paths   = path_rule.value.paths
          service = path_rule.value.backend
        }
      }
    }
  }
}

# Regional HTTPS URL MAP
resource "google_compute_region_url_map" "https" {
  for_each        = { for i, v in local.url_maps : v.index_key => v if v.is_regional }
  project         = each.value.project_id
  name            = "${each.value.name}-https"
  default_service = each.value.default_service
  dynamic "host_rule" {
    for_each = each.value.routing_rules
    content {
      path_matcher = host_rule.value.name
      hosts        = host_rule.value.hosts
    }
  }
  dynamic "path_matcher" {
    for_each = each.value.routing_rules
    content {
      name            = path_matcher.value.name
      default_service = coalesce(try(local.backend_ids[path_matcher.value.backend], null), local.default_service_id)
      dynamic "path_rule" {
        for_each = path_matcher.value.path_rules
        content {
          paths   = path_rule.value.paths
          service = path_rule.value.backend
        }
      }
    }
  }
  region = each.value.region
}
