#requires -Version 7.2

[CmdletBinding()]
param(
    [switch] $History
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git is required to scan repository content."
}

$repositoryRoot = (git rev-parse --show-toplevel).Trim()
if (-not $repositoryRoot) {
    throw "Run this script from inside a Git repository."
}

$blockedPaths = @(
    '^\.azure(?:/|$)',
    '^\.venv[^/]*(?:/|$)',
    '^infra/backend\.hcl$',
    '^infra/terraform\.tfvars$',
    '^infra/released-package\.zip$',
    '(?:^|/)\.terraform(?:/|$)',
    '\.tfstate(?:\..*)?$',
    '\.tfplan$',
    '^provider-schema\.json$',
    '^task_output\.txt$'
)

$placeholderGuid = '00000000-0000-0000-0000-000000000000'
$guid = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
$contentPatterns = [ordered]@{
    'Non-placeholder subscription resource ID' = "(?i)/subscriptions/(?!$placeholderGuid(?:/|\b))$guid"
    'Tenant-specific onmicrosoft.com address'   = '(?i)[a-z0-9._%+-]+@[a-z0-9.-]+\.onmicrosoft\.com'
    'Machine-specific Windows user path'        = '(?i)[a-z]:\\Users\\[^\\\s]+'
    'Signed callback URL'                       = '(?i)[?&]sig=[a-z0-9%_-]+'
    'Azure Storage account key'                 = '(?i)DefaultEndpointsProtocol=[^\r\n]+AccountKey='
    'Private key material'                      = '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'
    'GitHub token'                              = '(?i)gh[pousr]_[a-z0-9]{20,}'
    'Atlassian API token'                       = '(?i)ATATT[a-z0-9_-]{20,}'
    'JWT bearer token'                          = '(?i)eyJ[a-z0-9_-]{10,}\.eyJ[a-z0-9_-]{10,}\.[a-z0-9_-]{10,}'
    'Organization-specific policy exception'   = '(?i)SecurityControl.{0,12}Ignore\b'
}

$violations = [System.Collections.Generic.List[object]]::new()
$scannerPath = 'scripts/Test-PublicRepository.ps1'

function Test-PathPolicy {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Source
    )

    foreach ($pattern in $blockedPaths) {
        if ($Path -match $pattern) {
            $violations.Add([pscustomobject]@{
                Source = $Source
                Path = $Path
                Line = 0
                Rule = 'Private or generated path is tracked'
            })
            return
        }
    }
}

function Test-TextPolicy {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Text,
        [Parameter(Mandatory)][string] $Source
    )

    if ($Path -eq $scannerPath -or $Text.Contains([char]0)) {
        return
    }

    foreach ($entry in $contentPatterns.GetEnumerator()) {
        $matches = [regex]::Matches($Text, $entry.Value)
        foreach ($match in $matches) {
            $line = 1 + ($Text.Substring(0, $match.Index).Split("`n").Count - 1)
            $violations.Add([pscustomobject]@{
                Source = $Source
                Path = $Path
                Line = $line
                Rule = $entry.Key
            })
        }
    }

    $targetAssignments = [regex]::Matches(
        $Text,
        "(?i)(?:subscription_id|tenant_id)\s*=\s*[^\r\n]*?($guid)"
    )
    foreach ($match in $targetAssignments) {
        if ($match.Groups[1].Value -eq $placeholderGuid) {
            continue
        }

        $line = 1 + ($Text.Substring(0, $match.Index).Split("`n").Count - 1)
        $violations.Add([pscustomobject]@{
            Source = $Source
            Path = $Path
            Line = $line
            Rule = 'Non-placeholder Terraform Azure target'
        })
    }
}

$candidateFiles = @(git -C $repositoryRoot ls-files --cached --others --exclude-standard)
foreach ($relativePath in $candidateFiles) {
    Test-PathPolicy -Path $relativePath -Source 'working-tree'
    $fullPath = Join-Path $repositoryRoot $relativePath
    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        try {
            $text = [System.IO.File]::ReadAllText($fullPath)
            Test-TextPolicy -Path $relativePath -Text $text -Source 'working-tree'
        }
        catch [System.Text.DecoderFallbackException] {
            continue
        }
    }
}

if ($History) {
    $objects = @(git -C $repositoryRoot rev-list --objects --all)
    foreach ($object in $objects) {
        $parts = $object -split ' ', 2
        if ($parts.Count -ne 2) {
            continue
        }

        $objectId, $relativePath = $parts
        if ((git -C $repositoryRoot cat-file -t $objectId) -ne 'blob') {
            continue
        }

        Test-PathPolicy -Path $relativePath -Source "history:$objectId"
        if ($relativePath -eq $scannerPath) {
            continue
        }

        $text = git -C $repositoryRoot cat-file blob $objectId | Out-String
        Test-TextPolicy -Path $relativePath -Text $text -Source "history:$objectId"
    }
}

if ($violations.Count -gt 0) {
    $violations |
        Sort-Object Source, Path, Line, Rule -Unique |
        Format-Table Source, Path, Line, Rule -AutoSize |
        Out-String |
        Write-Error
    throw "Public repository safety scan found $($violations.Count) violation(s)."
}

$scope = if ($History) { 'public working-tree candidates and Git history' } else { 'public working-tree candidates' }
Write-Host "Public repository safety scan passed for $scope."
