locals {
  http_response_codes = {
    301 = "MOVED_PERMANENTLY_DEFAULT"
    302 = "FOUND"
    303 = "SEE_OTHER"
    307 = "TEMPORARY_REDIRECT"
    308 = "PERMANENT_REDIRECT"
  }
  _url_maps = [
    {
      create                 = coalesce(local.create, true)
      project_id             = local.project_id
      name                   = coalesce(var.url_map_name, var.name, local.name_prefix)
      is_application         = local.is_application
      is_regional            = local.is_regional
      region                 = local.region
      redirect_http_to_https = local.redirect_http_to_https
      ssl_certs              = local.ssl_certs
      routing_rules = [for i, v in coalesce(var.routing_rules, []) :
        {
          project_id                = coalesce(lookup(v, "project_id", null), local.project_id)
          name                      = coalesce(v.name, "path-matcher-${i + 1}")
          hosts                     = [for host in v.hosts : length(split(".", host)) > 1 ? host : "${host}.${v.domains[0]}"]
          path_rules                = coalesce(v.path_rules, [])
          request_headers_to_remove = v.request_headers_to_remove
          backend                   = v.backend
          redirect                  = lookup(v, "redirect", null)
        }
      ]
      default_service = var.name_prefix != null ? "${var.name_prefix}-${local.default_service}" : local.default_service
    }
  ]
  url_maps = [for i, v in local._url_maps :
    merge(v, {
      index_key = local.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }) if local.create == true && local.is_application == true
  ]
}

# Global URL Map for HTTP -> HTTPS redirect
resource "google_compute_url_map" "http-to-https" {
  for_each        = { for i, v in local.url_maps : v.index_key => v if v.is_application && v.redirect_http_to_https && !v.is_regional }
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
  for_each        = { for i, v in local.url_maps : v.index_key => v if v.is_application && v.redirect_http_to_https && v.is_regional }
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
      default_service = path_matcher.value.redirect != null ? null : coalesce(path_matcher.value.backend, each.value.default_service)
      dynamic "route_rules" {
        for_each = path_matcher.value.request_headers_to_remove != null ? [true] : []
        content {
          priority = coalesce(path_matcher.value.priority, 1)
          service  = try(coalesce(path_matcher.value.backend, path_matcher.key), null)
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
      dynamic "default_url_redirect" {
        for_each = path_matcher.value.redirect != null ? [path_matcher.value.redirect] : []
        content {
          host_redirect          = coalesce(default_url_redirect.value.host, "whamola.net")
          redirect_response_code = upper(startswith(default_url_redirect.value.code, "3") ? default_url_redirect.value.code : lookup(local.http_response_codes, default_url_redirect.value.code, "MOVED_PERMANENTLY_DEFAULT"))
          https_redirect         = coalesce(default_url_redirect.value.https, true)
          strip_query            = coalesce(default_url_redirect.value.strip_query, false)
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
