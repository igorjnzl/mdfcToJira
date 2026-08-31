#requires -Version 7.2

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string] $SubscriptionId,

    [Parameter(Mandatory)]
    [string] $Location,

    [string] $ResourceGroupName = "rg-mdc-jira-tfstate",
    [string] $StorageAccountName = "",
    [string] $ContainerName = "tfstate",
    [string] $StateKey = "mdc-jira/dev.tfstate",
    [string] $BackendConfigPath = "",
    [hashtable] $StorageTags = @{}
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI is required. Install it and run az login before this script."
}

$account = az account show --subscription $SubscriptionId --output json | ConvertFrom-Json
if (-not $account -or $account.state -ne "Enabled") {
    throw "Subscription $SubscriptionId is unavailable or disabled."
}

if (-not $StorageAccountName) {
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $seed = [System.Text.Encoding]::UTF8.GetBytes("$SubscriptionId|$ResourceGroupName")
        $hash = [System.BitConverter]::ToString($sha256.ComputeHash($seed)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
    $StorageAccountName = "stmdcjirastate$($hash.Substring(0, 8))"
}

if ($StorageAccountName -notmatch "^[a-z0-9]{3,24}$") {
    throw "StorageAccountName must contain 3-24 lowercase letters or digits."
}

if (-not $BackendConfigPath) {
    $BackendConfigPath = Join-Path $PSScriptRoot "..\infra\backend.hcl"
}
$BackendConfigPath = [System.IO.Path]::GetFullPath($BackendConfigPath)

$principalId = az ad signed-in-user show --query id --output tsv
if (-not $principalId) {
    throw "Could not resolve the signed-in user. Run az login with your user account."
}

$storageScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$StorageAccountName"
$storageTagArguments = @(
    "workload=mdc-jira-integration",
    "purpose=terraform-state",
    "managed-by=bootstrap"
)
foreach ($tag in $StorageTags.GetEnumerator()) {
    $storageTagArguments += "$($tag.Key)=$($tag.Value)"
}

if ($PSCmdlet.ShouldProcess("$ResourceGroupName/$StorageAccountName", "Create RBAC-only Terraform backend")) {
    az group create `
        --subscription $SubscriptionId `
        --name $ResourceGroupName `
        --location $Location `
        --tags workload=mdc-jira-integration purpose=terraform-state managed-by=bootstrap `
        --output none

    az storage account create `
        --subscription $SubscriptionId `
        --resource-group $ResourceGroupName `
        --name $StorageAccountName `
        --location $Location `
        --kind StorageV2 `
        --sku Standard_ZRS `
        --https-only true `
        --min-tls-version TLS1_2 `
        --allow-blob-public-access false `
        --allow-shared-key-access false `
        --default-action Allow `
        --public-network-access Enabled `
        --tags @storageTagArguments `
        --output none

    az storage container-rm create `
        --subscription $SubscriptionId `
        --resource-group $ResourceGroupName `
        --storage-account $StorageAccountName `
        --name $ContainerName `
        --public-access off `
        --output none

    $assignmentId = az role assignment list `
        --subscription $SubscriptionId `
        --assignee-object-id $principalId `
        --scope $storageScope `
        --role "Storage Blob Data Contributor" `
        --query "[0].id" `
        --output tsv

    if (-not $assignmentId) {
        az role assignment create `
            --subscription $SubscriptionId `
            --assignee-object-id $principalId `
            --assignee-principal-type User `
            --scope $storageScope `
            --role "Storage Blob Data Contributor" `
            --output none
    }

    $backendConfig = @"
resource_group_name  = "$ResourceGroupName"
storage_account_name = "$StorageAccountName"
container_name       = "$ContainerName"
key                  = "$StateKey"
subscription_id      = "$SubscriptionId"
tenant_id            = "$($account.tenantId)"
use_azuread_auth      = true
use_cli               = true
"@
    Set-Content -Path $BackendConfigPath -Value $backendConfig -Encoding utf8NoBOM
}

Write-Host "Backend configuration: $BackendConfigPath"
Write-Host "Initialize with: terraform -chdir=infra init -reconfigure -backend-config=backend.hcl"