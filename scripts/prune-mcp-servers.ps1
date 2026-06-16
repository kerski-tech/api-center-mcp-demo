param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$ApiCenterName,

    [string]$WorkspaceName = "default"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$serversPath = Join-Path $repoRoot "infra/mcp-servers"
$jsonFiles = Get-ChildItem -Path $serversPath -Filter "*.json" -File

$desiredNames = @{}
foreach ($file in $jsonFiles) {
    $content = Get-Content -Raw -Path $file.FullName | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($content.name)) {
        throw "Server file '$($file.Name)' is missing a non-empty 'name'."
    }
    $desiredNames[$content.name] = $true
}

$apisUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.ApiCenter/services/$ApiCenterName/workspaces/$WorkspaceName/apis?api-version=2024-06-01-preview"
$apis = az rest --method get --url $apisUrl | ConvertFrom-Json

foreach ($api in $apis.value) {
    $isMcp = $api.properties.kind -eq "mcp"
    $name = $api.name

    if ($isMcp -and -not $desiredNames.ContainsKey($name)) {
        Write-Host "Deleting unmanaged MCP API: $name"
        $deleteUrl = "https://management.azure.com$($api.id)?api-version=2024-06-01-preview"
        az rest --method delete --url $deleteUrl | Out-Null
    }
}

Write-Host "Pruning complete."
