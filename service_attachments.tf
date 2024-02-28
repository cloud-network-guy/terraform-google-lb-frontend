locals {
  _service_attachments = [for i, v in local.forwarding_rules :
    {
      create                    = coalesce(local.create, true)
      project_id                = v.project_id
      name                      = coalesce(var.psc.name, v.name)
      is_regional            = local.region != "global" ? true : false
      region                 = local.is_regional ? local.region : null
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
      nat_subnets = flatten([for ns in v.nat_subnets :
        [startswith("projects/", ns) ? ns : "projects/${v.host_project_id}/regions/${v.region}/subnetworks/${ns}"]
      ])
      accept_project_ids = [for p in v.accept_project_ids :
        {
          project_id       = p.project_id
          connection_limit = coalesce(p.connection_limit, 10)
        }
      ]
      target_service = try(google_compute_forwarding_rule.default[v.forwarding_rule_index_key].self_link, null)
      index_key      = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : null
    })
  ]
}

# Service Attachment (PSC Publish)
resource "google_compute_service_attachment" "default" {
  for_each              = { for k, v in local.service_attachments : v.index_key => v if v.is_regional }
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