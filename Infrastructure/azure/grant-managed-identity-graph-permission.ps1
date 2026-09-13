[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [Alias('mi')]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$ManagedIdentityPrincipalId
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Applications)) {
    throw 'Microsoft.Graph.Applications module is required. Install it with: Install-Module Microsoft.Graph -Scope CurrentUser'
}

Import-Module Microsoft.Graph.Applications

$requiredScopes = @('Application.Read.All', 'AppRoleAssignment.ReadWrite.All')
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

try {
    $managedIdentity = Get-MgServicePrincipal -ServicePrincipalId $ManagedIdentityPrincipalId
    $graphServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'" -Property 'appRoles'

    if (-not $graphServicePrincipal) {
        throw 'Microsoft Graph service principal was not found in this tenant.'
    }

    $groupMemberReadRole = $graphServicePrincipal.AppRoles | Where-Object {
        $_.Value -eq 'GroupMember.Read.All' -and $_.AllowedMemberTypes -contains 'Application'
    } | Select-Object -First 1

    if (-not $groupMemberReadRole) {
        throw 'The Microsoft Graph application role GroupMember.Read.All was not found.'
    }

    $existingAssignment = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $managedIdentity.Id -All | Where-Object {
            $_.ResourceId -eq $graphServicePrincipal.Id -and $_.AppRoleId -eq $groupMemberReadRole.Id
    }

    if ($existingAssignment) {
        Write-Host "No change: $($managedIdentity.DisplayName) already has GroupMember.Read.All." -ForegroundColor Yellow
        return
    }

    $assignment = @{
        PrincipalId = $managedIdentity.Id
        ResourceId  = $graphServicePrincipal.Id
        AppRoleId   = $groupMemberReadRole.Id
    }

    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $managedIdentity.Id -BodyParameter $assignment | Out-Null
    Write-Host "Granted GroupMember.Read.All to managed identity: $($managedIdentity.DisplayName)" -ForegroundColor Green
    Write-Host 'No Microsoft Graph write permissions were granted.' -ForegroundColor Green
}
finally {
    Disconnect-MgGraph | Out-Null
}
