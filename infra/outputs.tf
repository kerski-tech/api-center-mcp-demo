output "workspace_id" {
  value = azapi_resource.workspace.id
}

output "environment_id" {
  value = azapi_resource.environment.id
}

output "mcp_api_ids" {
  value = { for k, v in azapi_resource.mcp_api : k => v.id }
}
