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
