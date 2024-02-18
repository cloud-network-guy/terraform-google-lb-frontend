locals {
  _ssl_certs = [for i, v in var.ssl_certs :
    {
      create          = coalesce(v.create, local.create, true)
      project_id      = coalesce(v.project_id, local.project_id)
      name            = v.name != null ? lower(trimspace(replace(v.name, "_", "-"))) : "ssl-cert"
      name_prefix     = null #local.name_prefix
      description     = v.description
      is_regional     = v.region != null ? true : local.is_regional
      region          = try(coalesce(v.region, local.region), null)
      certificate     = lookup(v, "certificate", null) == null ? null : length(v.certificate) < 256 ? file("./${v.certificate}") : v.certificate
      private_key     = lookup(v, "private_key", null) == null ? null : length(v.private_key) < 256 ? file("./${v.private_key}") : v.private_key
      is_self_managed = lookup(v, "certificate", null) != null && lookup(v, "private_key", null) != null ? true : false
      domains         = coalesce(v.domains, [])
      ca_valid_years  = v.ca_valid_years
      ca_organization = v.ca_organization
    }
  ]
  ssl_certs = [for i, v in local._ssl_certs :
    merge(v, {
      is_self_signed  = v.certificate == null && v.private_key == null ? true : false
      is_self_managed = v.certificate == null && v.private_key == null ? true : v.is_self_managed # Self-signed certs will be self-managed as well
      index_key       = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
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
      index_key             = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
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
  for_each    = { for i, v in local.ssl_certs : v.index_key => v if !v.is_regional && v.is_self_managed }
  project     = each.value.project_id
  name        = each.value.name
  description = each.value.description
  name_prefix = each.value.name_prefix
  certificate = each.value.is_self_signed ? tls_self_signed_cert.default[each.value.index_key].cert_pem : each.value.certificate
  private_key = each.value.is_self_signed ? tls_private_key.default[each.value.index_key].private_key_pem : each.value.private_key
  lifecycle {
    create_before_destroy = true
  }
  depends_on = [null_resource.ssl_certs]
}

# Regional SSL Certs
resource "google_compute_region_ssl_certificate" "default" {
  for_each    = { for i, v in local.ssl_certs : v.index_key => v if v.is_regional && v.is_self_managed }
  project     = each.value.project_id
  name        = each.value.name
  description = each.value.description
  name_prefix = each.value.name_prefix
  certificate = each.value.is_self_signed ? tls_self_signed_cert.default[each.value.index_key].cert_pem : each.value.certificate
  private_key = each.value.is_self_signed ? tls_private_key.default[each.value.index_key].private_key_pem : each.value.private_key
  lifecycle {
    create_before_destroy = true
  }
  region     = each.value.region
  depends_on = [null_resource.ssl_certs]
}

# Google-Managed SSL certificates (Global only)
resource "google_compute_managed_ssl_certificate" "default" {
  for_each = { for i, v in local.ssl_certs : v.index_key => v if !v.is_self_managed && !v.is_regional }
  project  = each.value.project_id
  name     = each.value.name
  managed {
    domains = each.value.domains
  }
}
