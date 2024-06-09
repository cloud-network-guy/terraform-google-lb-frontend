resource "random_string" "random_name" {
  count   = var.name == null ? 1 : 0
  length  = 8
  lower   = true
  upper   = false
  special = false
  numeric = false
}

locals {
  url_prefix             = "https://www.googleapis.com/compute/v1/projects"
  create                 = coalesce(var.create, true)
  project_id             = lower(trimspace(var.project_id))
  host_project_id        = lower(trimspace(coalesce(var.host_project_id, local.project_id)))
  name_prefix            = var.name_prefix != null ? lower(trimspace(var.name_prefix)) : null
  name                   = var.name != null ? lower(trimspace(var.name)) : null
  description            = coalesce(var.description, "Managed by Terraform")
  is_regional            = var.region != null && var.region != "global" ? true : false
  region                 = local.is_regional ? var.region : "global"
  is_global              = !local.is_regional
  port                   = var.port
  protocol               = upper(coalesce(var.protocol, length(local.ports) > 0 || local.all_ports || local.is_psc ? "TCP" : "HTTP"))
  is_application         = startswith(local.protocol, "HTTP") ? true : false
  is_tcp                 = local.protocol == "TCP" && !local.is_application ? true : false
  network                = lower(trimspace(coalesce(var.network, "default")))
  subnet                 = lower(trimspace(coalesce(var.subnet, "default")))
  is_internal            = startswith(local.type, "INTERNAL") ? true : false
  type                   = upper(coalesce(var.type != null ? var.type : "EXTERNAL"))
  is_classic             = coalesce(var.classic, false)
  base_name              = var.name_prefix != null ? "${lower(trimspace(var.name_prefix))}-${local.name}" : local.name
  redirect_http_to_https = coalesce(var.redirect_http_to_https, local.enable_http ? true : false)
  ports                  = coalesce(var.ports, local.port != null ? [local.port] : [])
  http_port              = coalesce(var.http_port, 80)
  https_port             = coalesce(var.https_port, 443)
  is_psc                 = var.target != null ? true : false
  all_ports              = coalesce(var.all_ports, false)
  enable_http            = local.protocol == "HTTP" ? coalesce(var.enable_http, false) : false
  enable_https           = local.protocol == "HTTP" ? coalesce(var.enable_https, true) : false
  labels                 = { for k, v in coalesce(var.labels, {}) : k => lower(replace(v, " ", "_")) }
  create_static_ip       = coalesce(var.create_static_ip, true)
  ip_address             = var.ip_address
  ip_address_name        = coalesce(var.ip_address_name, local.base_name)
  enable_ipv4            = coalesce(var.enable_ipv4, true)
  enable_ipv6            = coalesce(var.enable_ipv6, false)
  ip_versions            = local.is_internal || local.is_regional ? ["IPV4"] : concat(local.enable_ipv4 ? ["IPV4"] : [], local.enable_ipv6 ? ["IPV6"] : [])
  preserve_ip            = coalesce(var.preserve_ip, false)
  is_mirroring_collector = false # TODO
  allow_global_access    = coalesce(var.global_access, false)
  target                 = try(coalesce(var.target, var.target_name), "none")
  default_service        = var.default_service
  existing_ssl_certs = var.existing_ssl_certs != null ? [for _ in var.existing_ssl_certs :
    coalesce(
      startswith(_, local.url_prefix) ? _ : null,
      startswith(_, "projects/") ? "${local.url_prefix}/${_}" : null,
      "${local.url_prefix}/${local.project_id}/${local.is_regional ? "regions/" : ""}${local.region}/sslCertificates/${_}"
    )
  ] : []
  port_names = {
    (local.http_port)  = "http"
    (local.https_port) = "https"
  }
  _forwarding_rules = [
    {
      create                  = local.create
      project_id              = local.project_id
      host_project_id         = local.host_project_id
      target_name             = coalesce(var.target_name, "none")
      target_project_id       = local.project_id
      target                  = local.target
      name                    = coalesce(var.forwarding_rule_name, local.base_name)
      type                    = local.type
      ip_protocol             = length(local.ports) > 0 || local.all_ports || local.is_psc ? "TCP" : "HTTP"
      region                  = local.region
      is_application          = local.is_application
      ports                   = local.ports
      all_ports               = local.is_psc || length(local.ports) > 0 ? false : local.all_ports
      network                 = local.network
      subnet                  = local.subnet
      network_tier            = local.protocol == "HTTP" && !local.is_internal ? "STANDARD" : null
      labels                  = length(local.labels) > 0 ? local.labels : null
      ip_address              = local.ip_address
      create_static_ip        = local.create_static_ip
      address_name            = local.ip_address_name
      enable_ipv4             = local.enable_ipv4
      enable_ipv6             = local.enable_ipv6
      preserve_ip             = local.preserve_ip
      is_mirroring_collector  = false # TODO
      is_classic              = local.is_classic
      ip_protocol             = local.is_psc || local.protocol == "HTTP" ? null : local.protocol
      allow_global_access     = local.is_internal && !local.is_psc ? local.allow_global_access : null
      allow_psc_global_access = local.is_psc && local.allow_global_access ? true : null
      load_balancing_scheme   = local.is_application && !local.is_classic ? "${local.type}_MANAGED" : local.type
      http_https_ports        = local.is_application ? concat(local.enable_http || local.redirect_http_to_https ? [local.http_port] : [], local.enable_https ? [local.https_port] : []) : []
      backend_service         = local.is_application ? null : local.default_service
      psc                     = var.psc
      source_ip_ranges        = [] # TODO
    }
  ]
  __forwarding_rules = flatten([for i, v in local._forwarding_rules :
    [for ip_port in setproduct(local.ip_versions, local.is_application ? v.http_https_ports : [0]) :
      merge(v, {
        port_range  = local.is_application ? ip_port[1] : null
        name        = local.is_application ? "${v.name}${local.enable_ipv6 ? "-${lower(ip_port[0])}" : ""}-${lookup(local.port_names, ip_port[1], "error")}" : v.name
        address_key = one([for _ in local.ip_addresses : _.index_key if _.forwarding_rule_name == v.name && _.region == v.region && _.ip_version == upper(ip_port[0])])
        target      = startswith(v.target, local.url_prefix) ? v.target : "${local.url_prefix}/${v.project_id}/${local.is_regional ? "regions/" : ""}${local.region}/targetHttp${(ip_port[1] != 80 ? "s" : "")}Proxies/${v.name}-${lookup(local.port_names, ip_port[1], "error")}"
        ip_version  = ip_port[0]
      })
    ]
  ])
  ___forwarding_rules = [for i, v in local.__forwarding_rules :
    merge(v, {
      ip_address = try(coalesce(
        local.is_psc ? google_compute_address.default["${v.project_id}/${v.region}/${v.address_name}"].self_link : null,
        v.ip_address,
        local.is_regional ? google_compute_address.default[v.address_key].address : null,
        !local.is_regional ? google_compute_global_address.default[v.address_key].address : null,
      ), null) # null address will allocate & use ephemeral IP
      target = local.is_application || local.is_psc ? v.target : null
    })
  ]
  forwarding_rules = [for i, v in local.___forwarding_rules :
    merge(v, {
      load_balancing_scheme = local.is_psc ? "" : v.load_balancing_scheme # null doesn't work with PSC forwarding rules
      subnetwork            = local.is_psc ? null : local.is_internal ? local.subnet : null
      index_key             = local.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }) if v.create == true
  ]
}

# Regional Forwarding rule
resource "google_compute_forwarding_rule" "default" {
  for_each                = { for i, v in local.forwarding_rules : v.index_key => v if local.is_regional }
  project                 = each.value.project_id
  name                    = each.value.name
  port_range              = each.value.port_range
  ports                   = each.value.ports
  all_ports               = each.value.all_ports
  backend_service         = each.value.backend_service
  target                  = each.value.target
  ip_address              = each.value.ip_address
  load_balancing_scheme   = each.value.load_balancing_scheme
  ip_protocol             = each.value.ip_protocol
  labels                  = each.value.labels
  is_mirroring_collector  = each.value.is_mirroring_collector
  network                 = each.value.network
  region                  = each.value.region
  subnetwork              = each.value.subnetwork
  network_tier            = each.value.network_tier
  allow_global_access     = each.value.allow_global_access
  allow_psc_global_access = each.value.allow_psc_global_access
  source_ip_ranges        = each.value.source_ip_ranges
  depends_on = [
    google_compute_address.default,
    google_compute_region_target_tcp_proxy.default,
    google_compute_region_target_http_proxy.default,
    google_compute_region_target_https_proxy.default,
  ]
}

# Global Forwarding rule
resource "google_compute_global_forwarding_rule" "default" {
  for_each              = { for i, v in local.forwarding_rules : v.index_key => v if local.is_global }
  project               = each.value.project_id
  name                  = each.value.name
  port_range            = each.value.port_range
  target                = each.value.target
  ip_address            = each.value.ip_address
  load_balancing_scheme = each.value.load_balancing_scheme
  ip_protocol           = each.value.ip_protocol
  labels                = each.value.labels
  source_ip_ranges      = each.value.source_ip_ranges
  depends_on = [
    google_compute_global_address.default,
    google_compute_target_tcp_proxy.default,
    google_compute_target_http_proxy.default,
    google_compute_target_https_proxy.default,
  ]
}
locals {
  _ip_addresses = [for i, v in local._forwarding_rules :
    {
      create               = v.create
      project_id           = v.project_id
      forwarding_rule_name = v.name
      address_type         = local.type
      name                 = local.ip_address_name
      description          = var.ip_address_description
      region               = v.region
      network              = "projects/${local.host_project_id}/global/networks/${v.network}"
      subnetwork           = local.is_regional && local.is_internal ? "projects/${local.host_project_id}/regions/${local.region}/subnetworks/${v.subnet}" : null
      purpose              = local.is_psc ? "GCE_ENDPOINT" : local.is_application && local.is_internal && local.redirect_http_to_https ? "SHARED_LOADBALANCER_VIP" : null
      network_tier         = local.is_psc ? null : v.network_tier
    } if v.create_static_ip == true
  ]
  __ip_addresses = flatten([for i, v in local._ip_addresses :
    [for ip_version in local.ip_versions :
      merge(v, {
        name = local.is_internal ? v.name : coalesce(
          ip_version == "IPV4" ? try(coalesce(var.ipv4_address_name, var.ip_address_name), null) : null,
          ip_version == "IPV6" ? try(coalesce(var.ipv6_address_name, var.ip_address_name), null) : null,
          "${v.name}-${lower(ip_version)}"
        )
        address = try(coalesce(
          ip_version == "IPV4" ? try(coalesce(var.ipv4_address, var.ip_address), null) : null,
          ip_version == "IPV6" ? try(coalesce(var.ipv6_address, var.ip_address), null) : null,
        ), null)
        ip_version = ip_version
      })
    ]
  ])
  ip_addresses = [for i, v in local.__ip_addresses :
    merge(v, {
      prefix_length = local.is_regional ? 0 : null
      index_key     = local.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }) if v.create == true && v.name != null
  ]
}

# Work-around for scenarios where PSC Consumer Endpoint IP changes
resource "null_resource" "ip_addresses" {
  for_each = { for i, v in local.ip_addresses : v.index_key => true if local.is_psc }
}

# Regional static IP
resource "google_compute_address" "default" {
  for_each      = { for i, v in local.ip_addresses : v.index_key => v if local.is_regional }
  project       = each.value.project_id
  name          = each.value.name
  description   = each.value.description
  address_type  = each.value.address_type
  ip_version    = each.value.ip_version
  address       = each.value.address
  region        = each.value.region
  subnetwork    = each.value.subnetwork
  network_tier  = each.value.network_tier
  purpose       = each.value.purpose
  prefix_length = each.value.prefix_length
  depends_on    = [null_resource.ip_addresses]
}

# Global static IP
resource "google_compute_global_address" "default" {
  for_each     = { for i, v in local.ip_addresses : v.index_key => v if local.is_global }
  project      = each.value.project_id
  name         = each.value.name
  address_type = each.value.address_type
  ip_version   = each.value.ip_version
  address      = each.value.address
}
locals {
  _service_attachments = [for i, v in local.forwarding_rules :
    {
      create                    = coalesce(local.create, true)
      project_id                = v.project_id
      name                      = coalesce(var.psc.name, v.name)
      is_regional               = local.region != "global" ? true : false
      region                    = local.region
      description               = coalesce(v.psc.description, "PSC Publish for '${v.name}'")
      reconcile_connections     = coalesce(v.psc.reconcile_connections, true)
      enable_proxy_protocol     = coalesce(v.psc.enable_proxy_protocol, false)
      auto_accept_all_projects  = coalesce(v.psc.auto_accept_all_projects, false)
      accept_project_ids        = coalesce(v.psc.accept_project_ids, [])
      consumer_reject_lists     = coalesce(v.psc.consumer_reject_lists, [])
      domain_names              = coalesce(v.psc.domain_names, [])
      host_project_id           = coalesce(v.psc.host_project_id, v.host_project_id, v.project_id)
      nat_subnets               = coalescelist(v.psc.nat_subnets, ["default"])
      forwarding_rule_index_key = v.index_key
    } if v.psc != null
  ]
  service_attachments = [for i, v in local._service_attachments :
    merge(v, {
      connection_preference = v.auto_accept_all_projects && length(v.accept_project_ids) == 0 ? "ACCEPT_AUTOMATIC" : "ACCEPT_MANUAL"
      nat_subnets = flatten([for _ in v.nat_subnets :
        [startswith("projects/", _) ? _ : "projects/${v.host_project_id}/regions/${v.region}/subnetworks/${_}"]
      ])
      accept_project_ids = [for p in v.accept_project_ids :
        {
          project_id       = p.project_id
          connection_limit = coalesce(p.connection_limit, 10)
        }
      ]
      target_service = try(google_compute_forwarding_rule.default[v.forwarding_rule_index_key].self_link, null)
      index_key      = local.is_regional ? "${v.project_id}/${v.region}/${v.name}" : null
    })
  ]
}

# Service Attachment aka PSC Publishing
resource "google_compute_service_attachment" "default" {
  for_each              = { for k, v in local.service_attachments : v.index_key => v if local.is_regional }
  project               = each.value.project_id
  name                  = each.value.name
  region                = each.value.region
  description           = each.value.description
  enable_proxy_protocol = each.value.enable_proxy_protocol
  nat_subnets           = each.value.nat_subnets
  target_service        = each.value.target_service
  connection_preference = each.value.connection_preference
  dynamic "consumer_accept_lists" {
    for_each = each.value.accept_project_ids
    content {
      project_id_or_num = consumer_accept_lists.value.project_id
      connection_limit  = consumer_accept_lists.value.connection_limit
    }
  }
  consumer_reject_lists = each.value.consumer_reject_lists
  domain_names          = each.value.domain_names
  reconcile_connections = each.value.reconcile_connections
  depends_on = [
    google_compute_forwarding_rule.default,
  ]
}

# SSL Certificates
locals {
  _ssl_certs = [for i, v in var.ssl_certs :
    {
      create          = coalesce(v.create, local.create)
      project_id      = coalesce(v.project_id, local.project_id)
      region          = local.region
      name            = lookup(v, "name", null) != null ? lower(trimspace(replace(v.name, "_", "-"))) : local.base_name
      description     = lookup(v, "description", null) != null ? trimspace(v.description) : null
      certificate     = lookup(v, "certificate", null) == null ? null : length(v.certificate) < 256 ? file("./${v.certificate}") : v.certificate
      private_key     = lookup(v, "private_key", null) == null ? null : length(v.private_key) < 256 ? file("./${v.private_key}") : v.private_key
      is_self_managed = lookup(v, "certificate", null) != null && lookup(v, "private_key", null) != null ? true : false
      name_prefix     = null
      domains         = coalesce(v.domains, [])
      ca_valid_years  = v.ca_valid_years
      ca_organization = v.ca_organization
    }
  ]
  ssl_certs = [for i, v in local._ssl_certs :
    merge(v, {
      is_self_signed  = v.certificate == null && v.private_key == null ? true : false
      is_self_managed = v.certificate == null && v.private_key == null ? true : v.is_self_managed
      index_key       = local.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }) if v.create == true
  ]
  self_signed_certs = [for i, v in local.ssl_certs :
    {
      common_name           = length(v.domains) > 0 ? v.domains[0] : "localhost.localdomain"
      organization          = trimspace(coalesce(v.ca_organization, "Honest Achmed's Used Cars and Certificates"))
      validity_period_hours = 24 * 365 * coalesce(v.ca_valid_years, 5)
      algorithm             = "RSA"
      rsa_bits              = 2048
      allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]
      index_key             = local.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    } if v.is_self_signed == true
  ]
}

# For self-signed, create a private key
resource "tls_private_key" "default" {
  for_each  = { for i, v in local.self_signed_certs : v.index_key => v }
  algorithm = each.value.algorithm
  rsa_bits  = each.value.rsa_bits
}
# Then generate a self-signed cert off that private key
resource "tls_self_signed_cert" "default" {
  for_each        = { for i, v in local.self_signed_certs : v.index_key => v }
  private_key_pem = tls_private_key.default[each.value.index_key].private_key_pem
  subject {
    common_name  = each.value.common_name
    organization = each.value.organization
  }
  validity_period_hours = each.value.validity_period_hours
  allowed_uses          = each.value.allowed_uses
}

# Create null resource for each cert so Terraform knows it must delete existing before creating new
resource "null_resource" "ssl_certs" {
  for_each = { for i, v in local.ssl_certs : v.index_key => true }
}

# Global SSL Certs
resource "google_compute_ssl_certificate" "default" {
  for_each    = { for i, v in local.ssl_certs : v.index_key => v if local.is_global && v.is_self_managed }
  project     = each.value.project_id
  name        = each.value.name
  description = each.value.description
  name_prefix = each.value.name_prefix
  certificate = each.value.is_self_signed ? tls_self_signed_cert.default[each.value.index_key].cert_pem : each.value.certificate
  private_key = each.value.is_self_signed ? tls_private_key.default[each.value.index_key].private_key_pem : each.value.private_key
  lifecycle {
    create_before_destroy = false
    ignore_changes        = [certificate, private_key]
  }
  depends_on = [null_resource.ssl_certs]
}

# Regional SSL Certs
resource "google_compute_region_ssl_certificate" "default" {
  for_each    = { for i, v in local.ssl_certs : v.index_key => v if local.is_regional && v.is_self_managed }
  project     = each.value.project_id
  name        = each.value.name
  description = each.value.description
  name_prefix = each.value.name_prefix
  certificate = each.value.is_self_signed ? tls_self_signed_cert.default[each.value.index_key].cert_pem : each.value.certificate
  private_key = each.value.is_self_signed ? tls_private_key.default[each.value.index_key].private_key_pem : each.value.private_key
  lifecycle {
    create_before_destroy = false
    ignore_changes        = [certificate, private_key]
  }
  region     = each.value.region
  depends_on = [null_resource.ssl_certs]
}

# Google-Managed SSL certificates (Global only)
resource "google_compute_managed_ssl_certificate" "default" {
  for_each = { for i, v in local.ssl_certs : v.index_key => v if local.is_global && !v.is_self_managed }
  project  = each.value.project_id
  name     = each.value.name
  managed {
    domains = each.value.domains
  }
}
locals {
  tls_versions = {
    "1"   = "TLS_1_0"
    "1_0" = "TLS_1_0"
    "1.0" = "TLS_1_0"
    "1_1" = "TLS_1_1"
    "1.1" = "TLS_1_1"
    "1_2" = "TLS_1_2"
    "1.2" = "TLS_1_2"
  }
  _ssl_policies = var.ssl_policy != null || var.min_tls_version != null ? [
    {
      create          = coalesce(lookup(var.ssl_policy, "create", null), local.create)
      project_id      = lower(trimspace(coalesce(lookup(var.ssl_policy, "project_id", null), local.project_id)))
      region          = local.region
      name            = lower(trimspace(coalesce(lookup(var.ssl_policy, "name", null), local.base_name)))
      description     = lookup(var.ssl_policy, "description", null) != null ? trimspace(var.ssl_policy.description) : null
      tls_profile     = upper(trimspace(coalesce(lookup(var.ssl_policy, "tls_profile", null), "MODERN")))
      min_tls_version = upper(trimspace(coalesce(lookup(var.ssl_policy, "min_tls_version", null), var.min_tls_version, "TLS_1_2")))
      region          = lower(trimspace(coalesce(lookup(var.ssl_policy, "region", null), local.region)))
    }
  ] : []
  ssl_policies = [for i, v in local._ssl_policies :
    merge(v, {
      min_tls_version = startswith(v.min_tls_version, "TLS_") ? v.min_tls_version : lookup(local.tls_versions, v.min_tls_version, "TLS_1_2")
      index_key       = local.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }) if v.create == true
  ]
}

# Global Custom SSL/TLS Policy
resource "google_compute_ssl_policy" "default" {
  for_each        = { for i, v in local.ssl_policies : v.index_key => v if local.is_global }
  project         = each.value.project_id
  name            = each.value.name
  description     = each.value.description
  profile         = each.value.tls_profile
  min_tls_version = each.value.min_tls_version
}

# Regional Custom SSL/TLS Policy
resource "google_compute_region_ssl_policy" "default" {
  for_each        = { for i, v in local.ssl_policies : v.index_key => v if local.is_regional }
  project         = each.value.project_id
  name            = each.value.name
  description     = each.value.description
  profile         = each.value.tls_profile
  min_tls_version = each.value.min_tls_version
  region          = each.value.region
}

locals {
  _target_http_proxies = local.is_application ? [for i, v in local.http_url_maps :
    merge(v, {
      create            = local.create
      project_id        = local.project_id
      region            = local.region
      name              = coalesce(var.target_http_proxy_name, "${local.base_name}-http")
      url_map_index_key = v.index_key
    })
  ] : []
  target_http_proxies = [for i, v in local._target_http_proxies :
    merge(v, {
      url_map   = local.is_regional ? google_compute_region_url_map.default[v.url_map_index_key].self_link : google_compute_url_map.default[v.url_map_index_key].self_link
      index_key = local.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }) if v.create == true
  ]
}

# Global HTTP Target Proxy
resource "google_compute_target_http_proxy" "default" {
  for_each   = { for i, v in local.target_http_proxies : v.index_key => v if local.is_application && local.is_global }
  project    = each.value.project_id
  name       = each.value.name
  url_map    = each.value.url_map
  depends_on = [google_compute_url_map.default]
}

# Regional HTTP Target Proxy
resource "google_compute_region_target_http_proxy" "default" {
  for_each   = { for i, v in local.target_http_proxies : v.index_key => v if local.is_application && local.is_regional }
  project    = each.value.project_id
  name       = each.value.name
  url_map    = each.value.url_map
  region     = each.value.region
  depends_on = [google_compute_region_url_map.default]
}

locals {
  _target_https_proxies = local.is_application ? [for i, v in local.https_url_maps :
    merge(v, {
      create            = local.create
      project_id        = local.project_id
      region            = local.region
      name              = coalesce(var.target_https_proxy_name, "${local.base_name}-https")
      url_map_index_key = v.index_key
    })
  ] : []
  __target_https_proxies = [for i, v in local._target_https_proxies :
    merge(v, {
      quic_override = upper(trimspace(coalesce(var.quic_override, "NONE")))
      ssl_policy = coalesce(
        var.existing_ssl_policy,
        local.is_global ? one([for _ in local.ssl_policies : google_compute_ssl_policy.default[_.index_key].self_link]) : null,
        local.is_regional ? one([for _ in local.ssl_policies : google_compute_region_ssl_policy.default[_.index_key].self_link]) : null,
      )
      ssl_certificates = concat(
        local.existing_ssl_certs,
        local.is_global ? [for _ in local.ssl_certs : google_compute_ssl_certificate.default[_.index_key].self_link] : [],
        local.is_regional ? [for _ in local.ssl_certs : google_compute_region_ssl_certificate.default[_.index_key].self_link] : [],
      )
    })
  ]
  target_https_proxies = [for i, v in local.__target_https_proxies :
    merge(v, {
      ssl_policy = startswith(v.ssl_policy, local.url_prefix) ? v.ssl_policy : "${local.url_prefix}/${local.project_id}/${local.is_regional ? "regions/" : ""}${local.region}/sslPolicies/${v.ssl_policy}"
      url_map    = local.is_regional ? google_compute_region_url_map.default[v.url_map_index_key].self_link : google_compute_url_map.default[v.url_map_index_key].self_link
      index_key  = local.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }) if v.create == true
  ]
}

# Global HTTPS Target Proxy
resource "google_compute_target_https_proxy" "default" {
  for_each         = { for i, v in local.target_https_proxies : v.index_key => v if local.is_global }
  project          = each.value.project_id
  name             = each.value.name
  url_map          = each.value.url_map
  ssl_certificates = each.value.ssl_certificates
  ssl_policy       = each.value.ssl_policy
  quic_override    = each.value.quic_override
  depends_on = [
    google_compute_url_map.default,
    google_compute_ssl_policy.default,
    null_resource.ssl_certs,
  ]
}

# Regional HTTPS Target Proxy
resource "google_compute_region_target_https_proxy" "default" {
  for_each         = { for i, v in local.target_https_proxies : v.index_key => v if local.is_regional }
  project          = each.value.project_id
  name             = each.value.name
  url_map          = each.value.url_map
  ssl_certificates = each.value.ssl_certificates
  ssl_policy       = each.value.ssl_policy
  region           = each.value.region
  depends_on = [
    google_compute_region_url_map.default,
    google_compute_region_ssl_policy.default,
    null_resource.ssl_certs,
  ]
}

locals {
  _target_tcp_proxies = local.is_tcp && !local.is_psc && !local.is_internal ? [
    {
      create          = local.create
      project_id      = local.project_id
      region          = local.region
      name            = coalesce(var.target_tcp_proxy_name, local.base_name)
      backend_service = local.default_service
    }
  ] : []
  target_tcp_proxies = [for i, v in local._target_tcp_proxies :
    merge(v, {
      index_key = local.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }) if v.create == true
  ]
}

# Global TCP Proxy
resource "google_compute_target_tcp_proxy" "default" {
  for_each        = { for i, v in local.target_tcp_proxies : v.index_key => v if local.is_global }
  project         = each.value.project_id
  name            = each.value.name
  backend_service = each.value.backend_service
}

# Regional TCP Proxy
resource "google_compute_region_target_tcp_proxy" "default" {
  for_each        = { for i, v in local.target_tcp_proxies : v.index_key => v if local.is_regional }
  project         = each.value.project_id
  name            = each.value.name
  backend_service = each.value.backend_service
  region          = each.value.region
}

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
      base_name              = coalesce(var.url_map_name, local.base_name)
      region                 = local.region
      redirect_http_to_https = local.redirect_http_to_https
      ssl_certs              = local.ssl_certs
      default_url_redirect   = local.redirect_http_to_https ? true : false
      routing_rules = [for i, v in coalesce(var.routing_rules, []) :
        {
          name                      = coalesce(lookup(v, "name", null), "path-matcher-${i + 1}")
          hosts                     = [for host in v.hosts : length(split(".", host)) > 1 ? host : "${host}.${v.domains[0]}"]
          path_rules                = coalesce(v.path_rules, [])
          redirect                  = lookup(v, "redirect", null)
          request_headers_to_remove = lookup(v, "request_headers_to_remove", null)
          backend                   = var.name_prefix != null ? "${var.name_prefix}-${v.backend}" : v.backend
        }
      ]
      default_service = var.name_prefix != null ? "${var.name_prefix}-${local.default_service}" : local.default_service
    }
  ] : []
  _http_url_maps = local.redirect_http_to_https ? [for i, v in local._url_maps :
    merge(v, {
      name                 = "${v.base_name}-http"
      default_service      = null
      default_url_redirect = true
      https_redirect       = true  #length(v.routing_rules) > 0 ? lookup(v.routing_rules.redirect, "https", true) : true
      strip_query          = false #length(v.routing_rules) > 0 ? lookup(v.routing_rules.redirect, "strip_query", false) : false
      routing_rules        = []
    })
  ] : []
  http_url_maps = [for i, v in local._http_url_maps :
    merge(v, {
      index_key = local.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }) if v.create == true
  ]

  _https_url_maps = [for i, v in local._url_maps :
    merge(v, {
      name                 = "${v.base_name}-https"
      default_service      = var.name_prefix != null ? "${var.name_prefix}-${local.default_service}" : local.default_service
      default_url_redirect = false
      https_redirect       = null
      strip_query          = null
    })
  ]
  https_url_maps = [for i, v in local._https_url_maps :
    merge(v, {
      index_key = local.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }) if v.create == true
  ]
  url_maps = concat(local.http_url_maps, local.https_url_maps)
}

# Create null resource for each URL Map so Terraform knows it must delete existing before creating new
resource "null_resource" "url_maps" {
  for_each = { for i, v in local.url_maps : v.index_key => true }
}

# Global HTTPS URL MAP
resource "google_compute_url_map" "default" {
  for_each        = { for i, v in local.url_maps : v.index_key => v if local.is_global }
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
  for_each        = { for i, v in local.url_maps : v.index_key => v if local.is_regional }
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
