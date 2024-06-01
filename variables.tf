variable "create" {
  type    = bool
  default = null
}
variable "project_id" {
  description = "GCP Project ID to create resources in"
  type        = string
}
variable "host_project_id" {
  description = "If using Shared VPC, the GCP Project ID for the host network"
  type        = string
  default     = null
}
variable "region" {
  description = "GCP region name for the IP address and forwarding rule"
  type        = string
  default     = null
}
variable "type" {
  type    = string
  default = null
}
variable "network" {
  type    = string
  default = null
}
variable "subnet" {
  type    = string
  default = null
}
variable "name_prefix" {
  type    = string
  default = null
}
variable "name" {
  type    = string
  default = null
}
variable "description" {
  type    = string
  default = null
}
variable "global_access" {
  type    = bool
  default = false
}
variable "default_service" {
  type    = string
  default = null
}
variable "enable_http" {
  type    = bool
  default = null
}
variable "enable_https" {
  type    = bool
  default = null
}
variable "redirect_http_to_https" {
  type    = bool
  default = null
}
variable "classic" {
  type    = bool
  default = null
}
variable "enable_ipv4" {
  type    = bool
  default = null
}
variable "enable_ipv6" {
  type    = bool
  default = null
}
variable "create_static_ip" {
  type    = bool
  default = null
}
variable "ip_address" {
  type    = string
  default = null
}
variable "ipv4_address" {
  type    = string
  default = null
}
variable "ipv6_address" {
  type    = string
  default = null
}
variable "ip_address_name" {
  type    = string
  default = null
}
variable "ipv4_address_name" {
  type    = string
  default = null
}
variable "ipv6_address_name" {
  type    = string
  default = null
}
variable "quic_override" {
  type    = bool
  default = null
}
variable "forwarding_rule_name" {
  type    = string
  default = null
}
variable "ipv4_forwarding_rule_name" {
  type    = string
  default = null
}
variable "ipv6_forwarding_rule_name" {
  type    = string
  default = null
}
variable "target_tcp_proxy_name" {
  type    = string
  default = null
}
variable "target_http_proxy_name" {
  type    = string
  default = null
}
variable "target_https_proxy_name" {
  type    = string
  default = null
}
variable "url_map_name" {
  type    = string
  default = null
}
variable "target" {
  type    = string
  default = null
}
variable "target_region" {
  type    = string
  default = null
}
variable "target_name" {
  type    = string
  default = null
}
variable "preserve_ip" {
  type    = bool
  default = null
}
variable "labels" {
  type    = map(string)
  default = null
}
variable "all_ports" {
  type    = bool
  default = null
}
variable "ports" {
  type    = list(number)
  default = null
}
variable "http_port" {
  type    = number
  default = null
}
variable "https_port" {
  type    = number
  default = null
}
variable "min_tls_version" {
  type    = string
  default = null
}
variable "existing_ssl_certs" {
  type    = list(string)
  default = null
}
variable "existing_ssl_policy" {
  type    = string
  default = null
}
variable "psc" {
  description = "Parameters to Publish this Frontend via PSC"
  type = object({
    create                   = optional(bool)
    project_id               = optional(string)
    host_project_id          = optional(string)
    name                     = optional(string)
    description              = optional(string)
    forwarding_rule_name     = optional(string)
    target_service_id        = optional(string)
    nat_subnets              = optional(list(string))
    enable_proxy_protocol    = optional(bool)
    auto_accept_all_projects = optional(bool)
    accept_project_ids = optional(list(object({
      project_id       = string
      connection_limit = optional(number)
    })))
    domain_names          = optional(list(string))
    consumer_reject_lists = optional(list(string))
    reconcile_connections = optional(bool)
  })
  default = null
}

variable "ssl_certs" {
  description = "List of SSL Certificates to upload to Google Certificate Manager"
  type = list(object({
    create          = optional(bool, true)
    project_id      = optional(string)
    name            = optional(string)
    description     = optional(string)
    certificate     = optional(string)
    private_key     = optional(string)
    region          = optional(string)
    domains         = optional(list(string))
    ca_organization = optional(string)
    ca_valid_years  = optional(number)
  }))
  default = []
}

variable "ssl_policy" {
  description = "Custom TLS policy"
  type = object({
    create          = optional(bool)
    project_id      = optional(string)
    name            = optional(string)
    description     = optional(string)
    min_tls_version = optional(string)
    tls_profile     = optional(string)
    region          = optional(string)
  })
  default = null
}

variable "routing_rules" {
  description = "List of Routing Rules for the URL Map"
  type = list(object({
    create                    = optional(bool, true)
    project_id                = optional(string)
    name                      = optional(string)
    priority                  = optional(number)
    hosts                     = list(string)
    backend                   = optional(string)
    path                      = optional(string)
    request_headers_to_remove = optional(list(string))
    redirect = optional(object({
      code        = optional(string)
      host        = optional(string)
      https       = optional(string)
      strip_query = optional(bool)
    }))
    path_rules = optional(list(object({
      paths        = list(string)
      backend_name = optional(string)
      backend      = string
    })))
  }))
  default = []
}