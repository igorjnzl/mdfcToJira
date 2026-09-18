[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $VaultName,

    [Parameter(Mandatory)]
    [string] $SubscriptionId,
    [string] $JiraBaseUrl = "",
    [string] $JiraUserEmail = "",
    [string] $JiraProjectKey = "",
    [string] $JiraEpicKey = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Get-Module -ListAvailable Az.KeyVault)) {
    throw "Az.KeyVault is required. Install-Module Az.KeyVault for the current user."
}

if (-not (Get-AzContext)) {
    Connect-AzAccount | Out-Null
}
Set-AzContext -Subscription $SubscriptionId | Out-Null

if (-not $JiraBaseUrl) { $JiraBaseUrl = Read-Host "Jira base URL (https://tenant.atlassian.net)" }
if (-not $JiraUserEmail) { $JiraUserEmail = Read-Host "Jira automation user email" }
if (-not $JiraProjectKey) { $JiraProjectKey = Read-Host "Jira project key" }
if (-not $JiraEpicKey) { $JiraEpicKey = Read-Host "Existing Jira epic key (for example AZ-123)" }
$JiraEpicKey = $JiraEpicKey.Trim()

if ($JiraBaseUrl -notmatch "^https://[^/]+$") {
    throw "JiraBaseUrl must be an HTTPS origin without a trailing path or slash."
}
if ($JiraUserEmail -notmatch "^[^@\s]+@[^@\s]+$") {
    throw "JiraUserEmail must be an email address."
}
if ($JiraProjectKey -notmatch "^[A-Za-z][A-Za-z0-9_]*$") {
    throw "JiraProjectKey contains unsupported characters."
}
if ($JiraEpicKey -notmatch "^[A-Za-z][A-Za-z0-9_]*-[1-9][0-9]*$") {
    throw "JiraEpicKey must be an existing epic's issue key, such as AZ-123."
}

$jiraApiToken = Read-Host "Jira API token" -AsSecureString
if ($jiraApiToken.Length -eq 0) {
    throw "Jira API token cannot be empty."
}

$secretValues = @{
    "jira-user-email"  = $JiraUserEmail
    "jira-base-url"    = $JiraBaseUrl.TrimEnd("/")
    "jira-project-key" = $JiraProjectKey
    "jira-epic-key"    = $JiraEpicKey
}

foreach ($secret in $secretValues.GetEnumerator()) {
    $secureValue = ConvertTo-SecureString $secret.Value -AsPlainText -Force
    Set-AzKeyVaultSecret -VaultName $VaultName -Name $secret.Key -SecretValue $secureValue | Out-Null
}
Set-AzKeyVaultSecret -VaultName $VaultName -Name "jira-api-token" -SecretValue $jiraApiToken | Out-Null

Write-Host "Configured five Jira secrets in Key Vault $VaultName. No secret values were written to Terraform state."