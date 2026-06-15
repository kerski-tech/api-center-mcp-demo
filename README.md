# Azure API Center private MCP registry with Terraform

This repository contains a Terraform-first version of the Azure API Center private MCP registry setup.

> Inspiration and credit: Joost Voskuil’s blog post, **“How to manage your private MCP registry on Azure API Center with Infrastructure as Code”** (June 14, 2026).

## Why Terraform for MCP registry management

Portal-based setup is great for demos, but Terraform gives you:

- pull-request based changes
- repeatable deployments across dev/test/prod
- drift control
- automated cleanup (pruning)
- disaster recovery from source control

## Architecture

```text
.
├── README.md
├── infra
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   └── mcp-servers
│       ├── figma-mcp-remote.json
│       └── playwright-mcp.json
└── scripts
    └── prune-mcp-servers.ps1
```

Use one JSON file per MCP server and keep server metadata in source control.

## Terraform implementation

### 1) Provider setup (`infra/providers.tf`)

```hcl
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azapi" {}
```

### 2) Variables (`infra/variables.tf`)

```hcl
variable "subscription_id" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "api_center_name" {
  type = string
}

variable "workspace_name" {
  type    = string
  default = "default"
}

variable "workspace_title" {
  type    = string
  default = "Default workspace"
}

variable "workspace_description" {
  type    = string
  default = "Default workspace"
}

variable "environment_name" {
  type    = string
  default = "default-mcp-env"
}

variable "environment_title" {
  type    = string
  default = "Default MCP Environment"
}

variable "environment_kind" {
  type    = string
  default = "Production"
}
```

### 3) Load JSON server definitions (`infra/main.tf`)

```hcl
locals {
  mcp_server_files = fileset("${path.module}/mcp-servers", "*.json")

  mcp_servers = {
    for file in local.mcp_server_files :
    trimsuffix(file, ".json") => jsondecode(file("${path.module}/mcp-servers/${file}"))
  }
}
```

### 4) Workspace + environment + MCP APIs (`infra/main.tf`)

```hcl
data "azurerm_client_config" "current" {}

locals {
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
        externalDocumentation = [each.value.externalDocumentation] # JSON file uses a single object; payload wraps it in an array
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
```

### Why `azapi_resource` instead of `azurerm_*`?

API Center MCP properties such as `remote`, `remoteType`, `securitySchemes`, and `authSchemas` are not fully exposed in strongly typed Terraform AzureRM resources. `azapi_resource` lets you pass the full ARM payload directly while keeping Terraform state and lifecycle management.

## JSON server examples

In server JSON files, set `externalDocumentation` as a **single object**. The Terraform resource shown above automatically wraps that object into an array for the ARM payload.

### Remote MCP server (`infra/mcp-servers/figma-mcp-remote.json`)

`externalDocumentation` remains an object in this JSON file; Terraform converts it to an array in the ARM payload.

```json
{
  "name": "figma-mcp",
  "title": "Figma MCP Server",
  "summary": "Brings Figma design context directly into your AI workflow.",
  "description": "The Figma MCP server brings Figma directly into your workflow by providing design information and context to AI agents generating code from Figma design files.",
  "kind": "mcp",
  "remote": "https://mcp.figma.com/mcp",
  "remoteType": "streamable-http",
  "externalDocumentation": {
    "title": "Figma MCP Server Guide",
    "url": "https://developers.figma.com/docs/figma-mcp-server/"
  },
  "versionName": "1-0-3",
  "customProperties": {
    "x-ms-preview": true
  }
}
```

### Package-based MCP server (`infra/mcp-servers/playwright-mcp.json`)

```json
{
  "name": "playwright-mcp",
  "title": "Playwright MCP Server",
  "summary": "Browser automation via MCP.",
  "description": "A Model Context Protocol server that provides browser automation capabilities using Playwright.",
  "kind": "mcp",
  "externalDocumentation": {
    "title": "Playwright MCP on npm",
    "url": "https://www.npmjs.com/package/@playwright/mcp"
  },
  "packages": [
    {
      "registry_name": "npm",
      "name": "@playwright/mcp",
      "version": "latest",
      "runtime_hint": "npx",
      "runtime_arguments": [],
      "package_arguments": [],
      "environment_variables": []
    }
  ],
  "versionName": "latest",
  "customProperties": {
    "x-ms-preview": false
  }
}
```

## Required fields (per server JSON)

- `name`
- `title`
- `summary`
- `description` (**must not be empty**; empty descriptions can make servers invisible in VS Code, enforced by the `lifecycle.precondition` block above)
- `kind` (`mcp`)
- `externalDocumentation`
- `versionName`
- `customProperties` (object, can be `{}`)

This example enforces non-empty descriptions via `lifecycle.precondition` in `azapi_resource.mcp_api`.

## Apply and deploy

```bash
cd infra
terraform init
terraform plan \
  -var "subscription_id=<subscription-guid>" \
  -var "resource_group_name=<rg-name>" \
  -var "api_center_name=<api-center-name>"
terraform apply \
  -var "subscription_id=<subscription-guid>" \
  -var "resource_group_name=<rg-name>" \
  -var "api_center_name=<api-center-name>"
```

## Pruning removed servers

Terraform only manages resources in state. If you remove a JSON file and want strict "code is source of truth" behavior, run a pruning step after apply.

Example approach (`scripts/prune-mcp-servers.ps1`):

1. Read desired server names from `infra/mcp-servers/*.json`
2. List APIs in the workspace via ARM REST API
3. Filter `kind == mcp`
4. Delete any API not present in the desired set

This mirrors the Bicep+PowerShell behavior from the original article.

## Operational notes

- Use PR reviews for any MCP server addition/removal.
- Keep one server definition per JSON file.
- Use separate Terraform workspaces or variable files for dev/test/prod.
- Prefer explicit version labels over mutable tags when possible.
