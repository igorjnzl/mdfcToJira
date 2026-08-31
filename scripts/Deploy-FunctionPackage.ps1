#requires -Version 7.2

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $SubscriptionId,

    [Parameter(Mandatory)]
    [string] $ResourceGroupName,

    [Parameter(Mandatory)]
    [string] $FunctionAppName,

    [Parameter(Mandatory)]
    [string] $PackagePath,

    [ValidateRange(60, 3600)]
    [int] $TimeoutSeconds = 1800
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

function ConvertFrom-JsonPrefix {
    param([Parameter(Mandatory)][string] $Text)

    $start = $Text.IndexOf("{")
    if ($start -lt 0) {
        throw "The response did not contain a JSON object."
    }

    $depth = 0
    $inString = $false
    $escaped = $false
    for ($index = $start; $index -lt $Text.Length; $index++) {
        $character = $Text[$index]
        if ($inString) {
            if ($escaped) {
                $escaped = $false
            }
            elseif ($character -eq "\") {
                $escaped = $true
            }
            elseif ($character -eq '"') {
                $inString = $false
            }
            continue
        }

        if ($character -eq '"') {
            $inString = $true
        }
        elseif ($character -eq "{") {
            $depth++
        }
        elseif ($character -eq "}") {
            $depth--
            if ($depth -eq 0) {
                return $Text.Substring($start, $index - $start + 1) | ConvertFrom-Json
            }
        }
    }

    throw "The response contained an incomplete JSON object."
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI is required for authenticated Flex Consumption One Deploy."
}

$resolvedPackage = (Resolve-Path -LiteralPath $PackagePath).Path
$account = az account show --subscription $SubscriptionId --output json | ConvertFrom-Json
if (-not $account -or $account.state -ne "Enabled") {
    throw "Subscription $SubscriptionId is unavailable or disabled."
}

$functionId = az functionapp show `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $FunctionAppName `
    --query id `
    --output tsv
if (-not $functionId) {
    throw "Function App $FunctionAppName was not found in $ResourceGroupName."
}

$deploymentStarted = [DateTimeOffset]::UtcNow
try {
    az functionapp deployment source config-zip `
        --subscription $SubscriptionId `
        --resource-group $ResourceGroupName `
        --name $FunctionAppName `
        --src $resolvedPackage `
        --build-remote true `
        --timeout $TimeoutSeconds `
        --only-show-errors `
        --output none
}
catch {
    $deploymentUrl = "https://management.azure.com$functionId/deployments?api-version=2022-03-01"
    $deploymentResponse = az rest --method get --url $deploymentUrl --output json | Out-String
    $deployments = (ConvertFrom-JsonPrefix -Text $deploymentResponse).value
    $latestDeployment = $deployments |
        Where-Object { $_.properties.deployer -eq "az_cli" } |
        Sort-Object { [DateTimeOffset]::Parse($_.properties.received_time) } -Descending |
        Select-Object -First 1

    $routes = az functionapp function list `
        --subscription $SubscriptionId `
        --resource-group $ResourceGroupName `
        --name $FunctionAppName `
        --output json |
        ConvertFrom-Json |
        ForEach-Object { $_.config.bindings } |
        Where-Object { $_.type -eq "httpTrigger" } |
        ForEach-Object { $_.route }

    $expectedRoutes = @("jira/requests", "defender/recommendations/assign")
    $missingRoutes = @($expectedRoutes | Where-Object { $_ -notin $routes })
    $isRecent = $latestDeployment -and (
        [DateTimeOffset]::Parse($latestDeployment.properties.received_time) -ge $deploymentStarted.AddMinutes(-1)
    )

    if (-not ($isRecent -and $latestDeployment.properties.complete -and $missingRoutes.Count -eq 0)) {
        throw
    }

    Write-Warning "Azure CLI status polling failed after upload, but a new completed deployment and both HTTP routes were verified."
}

Write-Host "Deployed $resolvedPackage to $FunctionAppName with authenticated One Deploy."