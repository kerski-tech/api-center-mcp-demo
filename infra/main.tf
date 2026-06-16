data "azurerm_client_config" "current" {}

locals {
  mcp_server_files = fileset("${path.module}/mcp-servers", "*.json")

  mcp_servers = {
    for file in local.mcp_server_files :
    trimsuffix(file, ".json") => jsondecode(file("${path.module}/mcp-servers/${file}"))
  }

  api_center_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.ApiCenter/services/${var.api_center_name}"
}

resource "azapi_resource" "workspace" {
  type      = "Microsoft.ApiCenter/services/workspaces@2024-06-01-preview"
  name      = var.workspace_name
  parent_id = local.api_center_id

  body = {
    properties = {
      title       = var.workspace_title
      description = var.workspace_description
    }
  }
}

resource "azapi_resource" "environment" {
  type      = "Microsoft.ApiCenter/services/workspaces/environments@2024-06-01-preview"
  name      = var.environment_name
  parent_id = azapi_resource.workspace.id

  body = {
    properties = {
      title            = var.environment_title
      kind             = var.environment_kind
      description      = "${var.workspace_name} MCP environment"
      customProperties = {}
    }
  }
}

resource "azapi_resource" "mcp_api" {
  for_each  = local.mcp_servers
  type      = "Microsoft.ApiCenter/services/workspaces/apis@2024-06-01-preview"
  name      = each.value.name
  parent_id = azapi_resource.workspace.id

  body = {
    properties = merge(
      {
        title                 = each.value.title
        summary               = each.value.summary
        description           = each.value.description
        kind                  = each.value.kind
        externalDocumentation = [each.value.externalDocumentation]
        customProperties      = each.value.customProperties
      },
      can(each.value.packages) ? { packages = each.value.packages } : {},
      can(each.value.vendor) ? { vendor = each.value.vendor } : {},
      can(each.value.icon) ? { icon = each.value.icon } : {},
      can(each.value.useCases) ? { useCases = each.value.useCases } : {},
      can(each.value.categories) ? { categories = each.value.categories } : {},
      can(each.value.supportContactInfo) ? { supportContactInfo = each.value.supportContactInfo } : {},
      can(each.value.license) ? { license = each.value.license } : {},
      can(each.value.remote) ? { remote = each.value.remote } : {},
      can(each.value.remoteType) ? { remoteType = each.value.remoteType } : {},
      can(each.value.securitySchemes) ? { securitySchemes = each.value.securitySchemes } : {},
      can(each.value.authSchemas) ? { authSchemas = each.value.authSchemas } : {},
      can(each.value.audience) ? { audience = each.value.audience } : {}
    )
  }

  lifecycle {
    precondition {
      condition     = trimspace(each.value.description) != ""
      error_message = "MCP server '${each.value.name}' must have a non-empty description."
    }
    precondition {
      condition     = trimspace(each.value.name) != ""
      error_message = "MCP server entry must have a non-empty name."
    }
    precondition {
      condition     = trimspace(each.value.title) != ""
      error_message = "MCP server '${each.value.name}' must have a non-empty title."
    }
    precondition {
      condition     = trimspace(each.value.summary) != ""
      error_message = "MCP server '${each.value.name}' must have a non-empty summary."
    }
    precondition {
      condition     = each.value.kind == "mcp"
      error_message = "MCP server '${each.value.name}' must set kind to 'mcp'."
    }
    precondition {
      condition     = can(each.value.externalDocumentation.title) && trimspace(each.value.externalDocumentation.title) != "" && can(each.value.externalDocumentation.url) && trimspace(each.value.externalDocumentation.url) != ""
      error_message = "MCP server '${each.value.name}' must include externalDocumentation.title and externalDocumentation.url."
    }
    precondition {
      condition     = trimspace(each.value.versionName) != ""
      error_message = "MCP server '${each.value.name}' must have a non-empty versionName."
    }
    precondition {
      condition     = can(each.value.customProperties)
      error_message = "MCP server '${each.value.name}' must include customProperties (can be {})."
    }
  }
}

resource "azapi_resource" "mcp_api_version" {
  for_each  = local.mcp_servers
  type      = "Microsoft.ApiCenter/services/workspaces/apis/versions@2024-06-01-preview"
  name      = each.value.versionName
  parent_id = azapi_resource.mcp_api[each.key].id

  body = {
    properties = {
      title          = each.value.versionName
      lifecycleStage = "production"
    }
  }
}

resource "azapi_resource" "mcp_api_definition" {
  for_each  = local.mcp_servers
  type      = "Microsoft.ApiCenter/services/workspaces/apis/versions/definitions@2024-06-01-preview"
  name      = "default-definition"
  parent_id = azapi_resource.mcp_api_version[each.key].id

  body = {
    properties = {
      title       = "Definition for ${each.value.title}"
      description = "Auto-generated definition for ${each.value.title}"
    }
  }
}

resource "azapi_resource" "mcp_api_deployment" {
  for_each = {
    for k, v in local.mcp_servers : k => v
    if can(v.remote)
  }

  type      = "Microsoft.ApiCenter/services/workspaces/apis/deployments@2024-06-01-preview"
  name      = "default-deployment"
  parent_id = azapi_resource.mcp_api[each.key].id

  body = {
    properties = {
      title         = "Deployment to ${var.environment_name}"
      environmentId = "${local.api_center_id}/workspaces/${var.workspace_name}/environments/${var.environment_name}"
      definitionId  = "${local.api_center_id}/workspaces/${var.workspace_name}/apis/${each.value.name}/versions/${each.value.versionName}/definitions/default-definition"
      server = {
        runtimeUri = [each.value.remote]
      }
      customProperties = each.value.customProperties
    }
  }

  depends_on = [
    azapi_resource.environment,
    azapi_resource.mcp_api_definition
  ]
}
