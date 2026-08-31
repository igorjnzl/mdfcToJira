# Defender for Cloud to Jira Integration

This repository deploys a Python 3.12 Azure Function App and a Consumption Logic App that create or find a Jira Service Management request for a Microsoft Defender for Cloud recommendation, then write the Jira reference back to a Defender governance assignment.

## Public Repository Safety

Environment-specific values belong only in ignored local files:

- `infra/terraform.tfvars`
- `infra/backend.hcl`
- `.azure/`
- generated Terraform state, plans, provider data, and deployment packages

The committed `.example` files contain placeholders only. Before committing or pushing, run:

```powershell
.\scripts\Test-PublicRepository.ps1
.\scripts\Test-PublicRepository.ps1 -History
```

The GitHub workflow runs the history scan on every push and pull request. It rejects tracked private paths, non-placeholder Azure subscription or tenant values, signed callback URLs, key material, token patterns, organization-specific policy exceptions, and machine-specific user paths.

## Deployment Model

- Function hosting: Linux Flex Consumption (`FC1`), Python 3.12
- Orchestration: multitenant Consumption Logic Apps
- Infrastructure: Terraform with an Azure Storage backend
- Target subscription, tenant, region, owner, and naming values: local `infra/terraform.tfvars`, which is ignored by Git

## Security Model

- The Logic App calls anonymous Function routes through Microsoft Entra Easy Auth using a user-assigned managed identity.
- Easy Auth returns HTTP 401 unless the caller token is issued for the Function API and belongs to the Logic App identity.
- The Function uses a separate user-assigned identity for Storage, Key Vault, Application Insights, and Defender.
- Terraform builds a deterministic source package and tracks an authenticated Azure CLI One Deploy step. Generated Python caches are excluded, the package remains private, and dependencies are built remotely for Linux.
- Storage shared-key access and anonymous blob access are disabled.
- Jira values are Key Vault references. Terraform creates no secret values.
- The PoC retains public routing for Function, Storage, Key Vault, and Azure Monitor endpoints. Authorization remains Entra/RBAC-based. Private endpoints require a connected VNet deployment runner and are deferred.
- Organization-specific policy tags are accepted through the local `data_service_tags` variable and backend bootstrap parameters. No policy exception is enabled by the public defaults.
- The Function identity receives subscription-scoped `Security Admin` for the PoC because Defender does not publish governance-assignment operations for a validated custom role. Replace this with a narrower role when Microsoft exposes a supported action set.
- The Jira HTTP action has automatic retries disabled to avoid duplicate requests after an ambiguous POST outcome. Defender write-back uses two bounded retries.

## Prerequisites

1. Azure CLI authenticated with MFA in the target tenant.
2. Terraform 1.10 or later.
3. Python 3.12 with the packages in `requirements-dev.txt`.
4. `Az.KeyVault` PowerShell module for secret bootstrap.
5. Permission to create resource groups, role assignments, and Entra applications in the target subscription and tenant.
6. Registered providers: `Microsoft.Web`, `Microsoft.Storage`, `Microsoft.Logic`, `Microsoft.Security`, `Microsoft.KeyVault`, `Microsoft.OperationalInsights`, `Microsoft.Insights`, and `Microsoft.ManagedIdentity`.

Confirm the target before any write:

```powershell
$subscriptionId = "<subscription-id>"
az account show --subscription $subscriptionId --query "{name:name,id:id,tenantId:tenantId}" -o table
az provider show --subscription $subscriptionId --namespace Microsoft.Logic --query registrationState -o tsv
```

## Validate Locally

```powershell
python -m pytest tests -q
python -m ruff check function_app tests
python -m mypy function_app/mdc_jira
terraform fmt -recursive -check
terraform -chdir=infra init -backend=false -reconfigure
terraform -chdir=infra validate
```

Checkov skips are documented next to the affected resources. Review every skip against your organization's requirements before deployment. Queue request logging uses the current `azurerm_storage_account_queue_properties` resource, while Blob read/write logging uses a diagnostic setting.

## Configure Terraform State

Preview, then create the dedicated RBAC-only state account:

```powershell
$subscriptionId = "<subscription-id>"
$location = "<azure-region>"

.\scripts\Initialize-TerraformBackend.ps1 -SubscriptionId $subscriptionId -Location $location -WhatIf
.\scripts\Initialize-TerraformBackend.ps1 -SubscriptionId $subscriptionId -Location $location
terraform -chdir=infra init -reconfigure -backend-config=backend.hcl
```

If an organization requires approved tags on the state account, pass them locally with `-StorageTags`. Do not add tenant-specific governance values to the script defaults or committed examples.

The generated `infra/backend.hcl` and all Terraform state files are ignored by Git. The state contains a signed Logic App callback URL, so keep the backend private and RBAC-restricted.
If backend initialization returns HTTP 403 immediately after bootstrap, allow the Blob Data Contributor assignment to propagate and rerun `terraform init`; do not enable storage keys.

## Plan And Deploy

Create an optional local variable file from the safe template and adjust only non-secret values:

```powershell
Copy-Item infra/terraform.tfvars.example infra/terraform.tfvars
terraform -chdir=infra plan -out=main.tfplan
terraform -chdir=infra show -no-color main.tfplan
```

Review the plan for the intended subscription and region, no unexpected deletes, and no unrelated changes. Applying creates billable Azure resources and subscription-level RBAC, so run it only after explicit deployment approval:

```powershell
terraform -chdir=infra apply main.tfplan
```

If package upload initially returns HTTP 403, wait for the new Blob Data Contributor assignment to propagate and rerun `terraform apply`. Do not enable storage account keys.

## Configure Jira

The Jira automation account must be able to search the Jira project and create requests for the selected service desk and request type. Confirm that the request type accepts `summary` and `description`.

After Terraform apply, populate Key Vault without exposing the API token in shell history:

```powershell
$subscriptionId = "<subscription-id>"
$resourceGroupName = terraform -chdir=infra output -raw resource_group_name
$vaultName = terraform -chdir=infra output -raw key_vault_name
.\scripts\Set-JiraKeyVaultSecrets.ps1 -SubscriptionId $subscriptionId -VaultName $vaultName

$functionName = terraform -chdir=infra output -raw function_app_name
az functionapp restart --subscription $subscriptionId --resource-group $resourceGroupName --name $functionName
```

Rerun the secret script to rotate any Jira value, then restart the Function App to refresh versionless Key Vault references immediately.

## Smoke Test

Use a real sandbox Defender recommendation and affected resource ID in `samples/defender-recommendation.json`. The included placeholders are not expected to support Defender write-back.

```powershell
$callback = terraform -chdir=infra output -raw logic_app_callback_url
$payload = Get-Content samples/defender-recommendation.json -Raw
Invoke-RestMethod -Method Post -Uri $callback -ContentType "application/json" -Body $payload
```

Verify the Logic App run, Jira request, and Defender governance assignment. Replay the same payload and confirm that the existing Jira request is returned rather than creating another ticket.

## Troubleshooting

- HTTP 401 from the Function: verify Easy Auth's audience and allowed application match the Function API client ID and Logic App identity client ID.
- Key Vault reference errors: verify `Key Vault Secrets User`, all six secret names, and restart the Function after role/secret propagation.
- Storage 403: verify shared keys remain disabled and both the deployer and Function identity data-plane roles have propagated.
- Logic App failed run: inspect the terminating action. It retains the Function HTTP status and structured response body.
- Defender 403: verify the Function identity's `Security Admin` assignment at the selected subscription.
- Defender 409: inspect whether another governance process owns the target assignment before retrying.

Microsoft Learn still documents Defender governance Create-or-Update with API version `2022-01-01-preview` as of 2026-08-31. Before production, revalidate that version, define assignment conflict ownership, add atomic external deduplication if concurrent events are possible, replace broad Defender RBAC, and evaluate VNet/private-endpoint deployment.