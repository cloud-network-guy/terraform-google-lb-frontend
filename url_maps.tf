locals {
  http_response_codes = {
    301 = "MOVED_PERMANENTLY_DEFAULT"
    302 = "FOUND"
    303 = "SEE_OTHER"
    307 = "TEMPORARY_REDIRECT"
    308 = "PERMANENT_REDIRECT"
  }
  _url_maps = local.is_application ? [
    {
      create                 = local.create
      project_id             = local.project_id
      type = local.type
      base_name              = coalesce(var.url_map_name, local.base_name)
      is_application         = local.is_application
      is_regional            = local.is_regional
      region                 = local.region
      redirect_http_to_https = local.redirect_http_to_https
      ssl_certs              = local.ssl_certs
      default_url_redirect   = local.redirect_http_to_https ? true : false
      routing_rules = [for i, v in coalesce(var.routing_rules, []) :
        {
          #project_id                = coalesce(lookup(v, "project_id", null), local.project_id)
          name                      = coalesce(v.name, "path-matcher-${i + 1}")
          hosts                     = [for host in v.hosts : length(split(".", host)) > 1 ? host : "${host}.${v.domains[0]}"]
          path_rules                = coalesce(v.path_rules, [])
          request_headers_to_remove = v.request_headers_to_remove
          backend                   = var.name_prefix != null ? "${var.name_prefix}-${v.backend}" : v.backend
          redirect                  = lookup(v, "redirect", null)
        }
      ]
      default_service = var.name_prefix != null ? "${var.name_prefix}-${local.default_service}" : local.default_service
    }
  ] : []
  http_url_maps = local.redirect_http_to_https ? [for i, v in local._url_maps :
    merge(v, {
      protocol             = "http"
      name                 = "${v.base_name}-http"
      default_service      = null
      default_url_redirect = true
      https_redirect       = true #length(v.routing_rules) > 0 ? lookup(v.routing_rules.redirect, "https", true) : true
      strip_query          = false #length(v.routing_rules) > 0 ? lookup(v.routing_rules.redirect, "strip_query", false) : false
      routing_rules = []
    })
  ] : []
  https_url_maps = [for i, v in local._url_maps :
    merge(v, {
      protocol             = "https"
      name                 = "${v.base_name}-https"
      default_service      = var.name_prefix != null ? "${var.name_prefix}-${local.default_service}" : local.default_service
      default_url_redirect = false
      https_redirect       = null
      strip_query          = null
    })
  ]
  url_maps = [for i, v in concat(local.http_url_maps, local.https_url_maps) :
    merge(v, {
      index_key = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }) if v.create == true
  ]
}

# Create null resource for each URL Map so Terraform knows it must delete existing before creating new
resource "null_resource" "url_maps" {
  for_each = { for i, v in local.url_maps : v.index_key => true }
}

# Global HTTPS URL MAP
resource "google_compute_url_map" "default" {
  for_each        = { for i, v in local.url_maps : v.index_key => v if !v.is_regional }
  project         = each.value.project_id
  name            = each.value.name
  default_service = each.value.default_service
  dynamic "default_url_redirect" {
    for_each = each.value.default_url_redirect ? [true] : []
    content {
      https_redirect = each.value.https_redirect
      strip_query    = each.value.strip_query
    }
  }
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
          host_redirect          = coalesce(default_url_redirect.value.host, "nowhere.net")
          redirect_response_code = upper(startswith(default_url_redirect.value.code, "3") ? lookup(local.http_response_codes, default_url_redirect.value.code, "MOVED_PERMANENTLY_DEFAULT") : default_url_redirect.value.code)
          https_redirect         = coalesce(default_url_redirect.value.https, true)
          strip_query            = coalesce(default_url_redirect.value.strip_query, false)
        }
      }
    }
  }
  depends_on = [null_resource.url_maps]
}

# Regional HTTPS URL MAP
resource "google_compute_region_url_map" "default" {
  for_each        = { for i, v in local.url_maps : v.index_key => v if v.is_regional }
  project         = each.value.project_id
  name            = each.value.name
  default_service = each.value.default_service
  dynamic "default_url_redirect" {
    for_each = each.value.default_url_redirect ? [true] : []
    content {
      https_redirect = each.value.https_redirect
      strip_query    = each.value.strip_query
    }
  }
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
      dynamic "path_rule" {
        for_each = path_matcher.value.path_rules
        content {
          paths   = path_rule.value.paths
          service = path_rule.value.backend
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
          host_redirect          = coalesce(default_url_redirect.value.host, "nowhere.net")
          redirect_response_code = upper(startswith(default_url_redirect.value.code, "3") ? lookup(local.http_response_codes, default_url_redirect.value.code, "MOVED_PERMANENTLY_DEFAULT") : default_url_redirect.value.code)
          https_redirect         = coalesce(default_url_redirect.value.https, true)
          strip_query            = coalesce(default_url_redirect.value.strip_query, false)
        }
      }
    }
  }
  region     = each.value.region
  depends_on = [null_resource.url_maps]
}
