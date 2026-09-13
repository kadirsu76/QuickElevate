[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [Alias('rg')]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [Alias('app')]
    [string]$FunctionAppName,

    [ValidatePattern('^(?:\d{1,3}\.){3}\d{1,3}(?:/\d{1,2})?$')]
    [string]$AllowedIp,

    [switch]$Disable
)

$ErrorActionPreference = 'Stop'
$az = if (Get-Command az -ErrorAction SilentlyContinue) { (Get-Command az).Source } elseif (Test-Path '/opt/homebrew/bin/az') { '/opt/homebrew/bin/az' } else { throw 'Azure CLI is required.' }
$siteId = & $az functionapp show --resource-group $ResourceGroupName --name $FunctionAppName --query id --output tsv

if ($Disable) {
    & $az webapp config access-restriction remove --resource-group $ResourceGroupName --name $FunctionAppName --rule-name 'Temporary-Operator-Access' --only-show-errors 2>$null
    & $az webapp config access-restriction remove --resource-group $ResourceGroupName --name $FunctionAppName --rule-name 'Temporary-Operator-SCM-Access' --scm-site true --only-show-errors 2>$null
    & $az resource update --ids $siteId --api-version '2024-04-01' --set 'properties.publicNetworkAccess=Disabled' --only-show-errors | Out-Null
    Write-Host 'Temporary public access disabled. Private Endpoint remains the only network path.' -ForegroundColor Green
    exit 0
}

if (-not $AllowedIp) {
    throw 'AllowedIp is required unless -Disable is used. Example: -AllowedIp 188.119.54.129/32'
}
if ($AllowedIp -notmatch '/') {
    $AllowedIp = "$AllowedIp/32"
}

& $az resource update --ids $siteId --api-version '2024-04-01' --set 'properties.publicNetworkAccess=Enabled' --only-show-errors | Out-Null
& $az webapp config access-restriction remove --resource-group $ResourceGroupName --name $FunctionAppName --rule-name 'Temporary-Operator-Access' --only-show-errors 2>$null
& $az webapp config access-restriction remove --resource-group $ResourceGroupName --name $FunctionAppName --rule-name 'Temporary-Operator-SCM-Access' --scm-site true --only-show-errors 2>$null
& $az webapp config access-restriction add --resource-group $ResourceGroupName --name $FunctionAppName --rule-name 'Temporary-Operator-Access' --action Allow --ip-address $AllowedIp --priority 100 --description 'Temporary operator access; remove after VPN/GSA is ready' --only-show-errors | Out-Null
& $az webapp config access-restriction add --resource-group $ResourceGroupName --name $FunctionAppName --rule-name 'Temporary-Operator-SCM-Access' --action Allow --ip-address $AllowedIp --priority 100 --description 'Temporary SCM deployment access; remove after VPN/GSA is ready' --scm-site true --only-show-errors | Out-Null
& $az webapp config access-restriction set --resource-group $ResourceGroupName --name $FunctionAppName --default-action Deny --scm-default-action Deny --use-same-restrictions-for-scm-site false --only-show-errors | Out-Null

Write-Host "Temporary public access enabled for $AllowedIp only. API and SCM default actions are Deny." -ForegroundColor Yellow
