locals {
  _ssl_certs = [for i, v in var.ssl_certs :
    {
      create          = coalesce(v.create, true)
      project_id      = var.project_id
      name            = replace(coalesce(v.name, element(split(".", v.certificate), 0)), "_", "-")
      name_prefix     = null
      description     = v.description
      region          = try(coalesce(v.region, var.region), null)
      is_regional     = try(coalesce(v.region, var.region), null) != null ? true : false
      certificate     = length(v.certificate) < 256 ? file("./${v.certificate}") : v.certificate
      private_key     = length(v.private_key) < 256 ? file("./${v.private_key}") : v.private_key
      is_self_managed = v.certificate != null && v.private_key != null ? true : false
      is_self_signed  = false
    }
  ]
  ssl_certs = [for i, v in local._ssl_certs :
    merge(v, {
      index_key = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }) if v.create == true
  ]
  self_signed_certs = [for i, v in local.ssl_certs :
    {
      common_name           = coalesce(v.domains != null ? v.domains[0] : "localhost.localdomain")
      organization          = coalesce(v.ca_organization, "Honest Achmed's Used Cars and Certificates")
      validity_period_hours = 24 * 365 * coalesce(v.valid_years, 5)
      algorithm             = upper("RSA")
      rsa_bits              = 2048
      allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]
      index_key             = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    } if v.is_self_signed == true
  ]
}

# For self-signed, create a private key
resource "tls_private_key" "default" {
  for_each  = { for i, v in local.self_signed_certs : v.index_key => v }
  algorithm = each.value.key_algorithm
  rsa_bits  = each.value.key_bits
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

# Upload Global SSL Certs
resource "google_compute_ssl_certificate" "default" {
  for_each    = { for i, v in local.ssl_certs : v.index_key => v if !v.is_regional && v.is_self_managed }
  project     = each.value.project_id
  name        = each.value.name
  description = each.value.description
  name_prefix = each.value.name_prefix
  certificate = each.value.certificate
  private_key = each.value.private_key
  lifecycle {
    create_before_destroy = true
  }
}

# Upload Regional SSL Certs
resource "google_compute_region_ssl_certificate" "default" {
  for_each    = { for i, v in local.ssl_certs : v.index_key => v if v.is_regional && v.is_self_managed }
  project     = each.value.project_id
  name        = each.value.name
  description = each.value.description
  name_prefix = each.value.name_prefix
  certificate = each.value.certificate
  private_key = each.value.private_key
  lifecycle {
    create_before_destroy = true
  }
  region = each.value.region
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
