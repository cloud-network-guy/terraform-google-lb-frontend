locals {
  lb_frontends = var.lb_frontends
  _url_maps = [for i, v in local.lb_frontends :
    {
      create      = coalesce(v.create, true)
      project_id  = var.project_id
      name        = "likasjfd"
      region      = v.region
      is_regional = var.region != null ? true : false
    } if v.is_application == true
  ]
  url_maps = [for i, v in local._url_maps :
    merge(v, {
      index_key = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }) if v.create == true
  ]
}

# Global URL Map for HTTP -> HTTPS redirect
resource "google_compute_url_map" "http" {
  for_each        = { for i, v in local.url_maps : v.index_key => v if !v.is_regional }
  project         = each.value.project_id
  name            = each.value.name
  default_service = null
  default_url_redirect {
    https_redirect = true
    strip_query    = false
  }
}

# Regional URL Map for HTTP -> HTTPS redirect
resource "google_compute_region_url_map" "http" {
  for_each        = { for i, v in local.url_maps : v.index_key => v if v.is_regional }
  project         = each.value.project_id
  name            = each.value.name
  default_service = null
  default_url_redirect {
    https_redirect = true
    strip_query    = false
  }
  region = each.value.region
}

locals {
  routing_rules = flatten([for lb_frontend in var.lb_frontends :
    [for i, v in coalesce(lb_frontend.routing_rules, []) :
      merge(v, {
        name       = coalesce(v.name, "path-matcher-${i + 1}")
        hosts      = [for host in v.hosts : length(split(".", host)) > 1 ? host : "${host}.${v.domains[0]}"]
        path_rules = coalesce(v.path_rules, [])
      })
    ]
  ])
}

# Global HTTPS URL MAP
resource "google_compute_url_map" "https" {
  for_each        = { for i, v in local.url_maps : v.index_key => v if !v.is_regional }
  project         = each.value.project_id
  name            = each.value.name
  default_service = each.value.default_service
  dynamic "host_rule" {
    for_each = each.value.host_rule
    content {
      path_matcher = host_rule.value.patch_matcher
      hosts        = host_rule.value.hosts
    }
  }
  dynamic "path_matcher" {
    for_each = local.routing_rules
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
  name            = each.value.name
  default_service = each.value.default_service
  dynamic "host_rule" {
    for_each = local.routing_rules
    content {
      path_matcher = host_rule.value.name
      hosts        = host_rule.value.hosts
    }
  }
  dynamic "path_matcher" {
    for_each = local.routing_rules
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
