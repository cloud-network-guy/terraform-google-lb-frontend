locals {
  url_prefix             = "https://www.googleapis.com/compute/v1/projects"
  create                 = coalesce(var.create, true)
  project_id             = var.project_id
  host_project_id        = coalesce(var.host_project_id, local.project_id)
  name_prefix            = var.name_prefix != null ? lower(trimspace(var.name_prefix)) : null
  description            = coalesce(var.description, "Managed by Terraform")
  region                 = local.is_regional ? var.region : "global"
  redirect_http_to_https = coalesce(var.redirect_http_to_https, local.enable_http ? true : false)
  ports                  = coalesce(var.ports, [])
  http_port              = coalesce(var.http_port, 80)
  https_port             = coalesce(var.https_port, 443)
  all_ports              = coalesce(var.all_ports, false)
  ip_protocol            = length(local.ports) > 0 || local.all_ports ? "TCP" : "HTTP"
  is_application         = local.ip_protocol == "HTTP" ? true : false
  enable_http            = local.ip_protocol == "HTTP" ? coalesce(var.enable_http, false) : false
  enable_https           = local.ip_protocol == "HTTP" ? coalesce(var.enable_https, true) : false
  network                = coalesce(var.network, "default")
  subnet                 = coalesce(var.subnet, "default")
  labels                 = { for k, v in coalesce(var.labels, {}) : k => lower(replace(v, " ", "_")) }
  ip_address             = var.ip_address
  ip_address_name        = coalesce(var.ip_address_name, local.name_prefix)
  enable_ipv4            = coalesce(var.enable_ipv4, true)
  enable_ipv6            = coalesce(var.enable_ipv6, false)
  ip_versions            = local.is_internal || local.is_regional ? ["IPV4"] : concat(local.enable_ipv4 ? ["IPV4"] : [], local.enable_ipv6 ? ["IPV6"] : [])
  preserve_ip            = coalesce(var.preserve_ip, false)
  is_mirroring_collector = false # TODO
  allow_global_access    = coalesce(var.global_access, false)
  #backend_service        = try(coalesce(v.backend_service_id, v.backend_service, v.backend_service_name), null)
  target          = try(coalesce(var.target, var.target_name), null)
  default_service = var.default_service
  is_regional     = try(coalesce(var.region, var.target_region, var.subnet), null) != null ? true : false
  is_internal     = var.subnet != null ? true : false
  network_tier    = local.ip_protocol == "HTTP" && !local.is_internal ? "STANDARD" : null
  type            = local.is_internal ? "INTERNAL" : "EXTERNAL"
  is_classic      = coalesce(var.classic, false)
  is_psc          = var.target != null ? true : false
}
