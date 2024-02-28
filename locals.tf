locals {
  url_prefix             = "https://www.googleapis.com/compute/v1/projects"
  create                 = coalesce(var.create, true)
  project_id             = lower(trimspace(var.project_id))
  host_project_id        = coalesce(var.host_project_id, local.project_id)
  name_prefix            = var.name_prefix != null ? lower(trimspace(var.name_prefix)) : null
  name                   = var.name != null ? lower(trimspace(var.name)) : null
  description            = coalesce(var.description, "Managed by Terraform")
  is_regional            = var.region != null && var.region != "global" ? true : var.subnet != null ? true : false
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
  network                = lower(trimspace(coalesce(var.network, "default")))
  subnet                 = lower(trimspace(coalesce(var.subnet, "default")))
  labels                 = { for k, v in coalesce(var.labels, {}) : k => lower(replace(v, " ", "_")) }
  ip_address             = var.ip_address
  ip_address_name        = try(coalesce(var.ip_address_name, local.name, local.name_prefix), null)
  enable_ipv4            = coalesce(var.enable_ipv4, true)
  enable_ipv6            = coalesce(var.enable_ipv6, false)
  ip_versions            = local.is_internal || local.is_regional ? ["IPV4"] : concat(local.enable_ipv4 ? ["IPV4"] : [], local.enable_ipv6 ? ["IPV6"] : [])
  preserve_ip            = coalesce(var.preserve_ip, false)
  is_mirroring_collector = false # TODO
  allow_global_access    = coalesce(var.global_access, false)
  target                 = try(coalesce(var.target, var.target_name), null)
  default_service        = var.default_service
  is_internal            = var.subnet != null ? true : false
  network_tier           = local.ip_protocol == "HTTP" && !local.is_internal ? "STANDARD" : null
  type                   = local.is_internal ? "INTERNAL" : "EXTERNAL"
  load_balancing_scheme  = local.is_application && !local.is_classic ? "${local.type}_MANAGED" : local.type
  is_classic             = coalesce(var.classic, false)
  is_psc                 = var.target != null ? true : false
  # Convert SSL certificates list to full URLs
  ssl_certificates = var.ssl_certificates != null ? [for _ in var.ssl_certificates :
    coalesce(
      startswith(_, local.url_prefix) ? _ : null,
      startswith(_, "projects/") ? "https://www.googleapis.com/compute/v1/${_}" : null,
      "${local.url_prefix}/${local.project_id}/${(local.is_regional ? "regions/${local.region}" : "global")}/sslCertificates/${_}"
    )
  ] : []
}
