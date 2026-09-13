[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [Alias('rg')]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [Alias('app')]
    [string]$FunctionAppName,

    [switch]$PublishFunctionCode
)

$ErrorActionPreference = 'Stop'

function Require-Command([string]$Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $macOSHomebrewPath = "/opt/homebrew/bin/$Name"
    if ($IsMacOS -and (Test-Path $macOSHomebrewPath)) {
        return $macOSHomebrewPath
    }

    throw "Required command not found: $Name"
}

function Get-OrCreate-Application([string]$DisplayName, [bool]$PublicClient) {
    $application = Get-MgApplication -Filter "displayName eq '$DisplayName'" -All | Select-Object -First 1
    if ($application) {
        return $application
    }

    $body = @{
        DisplayName = $DisplayName
        SignInAudience = 'AzureADMyOrg'
    }

    if ($PublicClient) {
        $body.IsFallbackPublicClient = $true
        $body.PublicClient = @{
            RedirectUris = @('http://localhost')
        }
    }

    return New-MgApplication -BodyParameter $body
}

function Get-OrCreate-ServicePrincipal([string]$AppId) {
    $servicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$AppId'" -All | Select-Object -First 1
    if (-not $servicePrincipal) {
        $servicePrincipal = New-MgServicePrincipal -AppId $AppId
    }
    return $servicePrincipal
}

$az = Require-Command az

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Applications) -or
    -not (Get-Module -ListAvailable -Name Microsoft.Graph.Identity.SignIns) -or
    -not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    throw 'Microsoft Graph PowerShell SDK is required. Run: Install-Module Microsoft.Graph -Scope CurrentUser'
}

Import-Module Microsoft.Graph.Applications
Import-Module Microsoft.Graph.Identity.SignIns
Import-Module Microsoft.Graph.Authentication

$account = & $az account show --output json | ConvertFrom-Json
$tenantId = $account.tenantId
    $functionApp = & $az functionapp show --resource-group $ResourceGroupName --name $FunctionAppName --output json | ConvertFrom-Json
$managedIdentity = $functionApp.identity.userAssignedIdentities.PSObject.Properties.Value | Select-Object -First 1

if (-not $managedIdentity.principalId) {
    throw 'The Function App does not have a user-assigned managed identity. Deploy the current infrastructure template first.'
}

$apiDisplayName = "QuickElevate API - $FunctionAppName"
$nativeDisplayName = "QuickElevate macOS - $FunctionAppName"
$requiredScopes = @(
    'Application.ReadWrite.All',
    'AppRoleAssignment.ReadWrite.All',
    'DelegatedPermissionGrant.ReadWrite.All'
)

Connect-MgGraph -TenantId $tenantId -Scopes $requiredScopes -ContextScope Process -NoWelcome

if (-not (Get-MgContext)) {
    throw 'Microsoft Graph authentication did not create a usable session.'
}

try {
    $apiApplication = Get-OrCreate-Application -DisplayName $apiDisplayName -PublicClient $false
    $scopeName = 'Elevation.Request'
    $apiApplication = Get-MgApplication -ApplicationId $apiApplication.Id
    $scope = $apiApplication.Api.Oauth2PermissionScopes | Where-Object { $_.Value -eq $scopeName } | Select-Object -First 1

    if (-not $scope) {
        $scope = @{
            Id = [guid]::NewGuid()
            AdminConsentDisplayName = 'Request temporary local administrator elevation'
            AdminConsentDescription = 'Allows the signed-in user to request a temporary local administrator elevation.'
            UserConsentDisplayName = 'Request temporary local administrator elevation'
            UserConsentDescription = 'Allows the signed-in user to request a temporary local administrator elevation.'
            IsEnabled = $true
            Type = 'User'
            Value = $scopeName
        }
        Update-MgApplication -ApplicationId $apiApplication.Id -Api @{ Oauth2PermissionScopes = @($scope) }
        $apiApplication = Get-MgApplication -ApplicationId $apiApplication.Id
        $scope = $apiApplication.Api.Oauth2PermissionScopes | Where-Object { $_.Value -eq $scopeName } | Select-Object -First 1
    }

    $apiServicePrincipal = Get-OrCreate-ServicePrincipal -AppId $apiApplication.AppId
    $nativeApplication = Get-OrCreate-Application -DisplayName $nativeDisplayName -PublicClient $true
    $nativeServicePrincipal = Get-OrCreate-ServicePrincipal -AppId $nativeApplication.AppId

    $requiredResourceAccess = @{
        ResourceAppId = $apiApplication.AppId
        ResourceAccess = @(
            @{
                Id = $scope.Id
                Type = 'Scope'
            }
        )
    }
    Update-MgApplication -ApplicationId $nativeApplication.Id -RequiredResourceAccess @($requiredResourceAccess)

    $existingGrant = Get-MgOauth2PermissionGrant -Filter "clientId eq '$($nativeServicePrincipal.Id)' and resourceId eq '$($apiServicePrincipal.Id)'" -All | Select-Object -First 1
    if (-not $existingGrant) {
        New-MgOauth2PermissionGrant -BodyParameter @{
            ClientId = $nativeServicePrincipal.Id
            ConsentType = 'AllPrincipals'
            ResourceId = $apiServicePrincipal.Id
            Scope = $scopeName
        } | Out-Null
    }

    $existingSettings = & $az functionapp config appsettings list --resource-group $ResourceGroupName --name $FunctionAppName --output json | ConvertFrom-Json
    $hasEasyAuthSecret = $existingSettings | Where-Object { $_.name -eq 'MICROSOFT_PROVIDER_AUTHENTICATION_SECRET' } | Select-Object -First 1
    $appSettings = @(
        "QUICK_ELEVATE_NATIVE_CLIENT_ID=$($nativeApplication.AppId)"
        "QUICK_ELEVATE_API_APPLICATION_ID=$($apiApplication.AppId)"
    )

    if (-not $hasEasyAuthSecret) {
        $secret = Add-MgApplicationPassword -ApplicationId $apiApplication.Id -PasswordCredential @{
            DisplayName = "Easy Auth - $FunctionAppName"
            EndDateTime = [DateTime]::UtcNow.AddYears(1)
        }
        $appSettings += "MICROSOFT_PROVIDER_AUTHENTICATION_SECRET=$($secret.SecretText)"
    }

    & $az functionapp config appsettings set `
        --resource-group $ResourceGroupName `
        --name $FunctionAppName `
        --settings $appSettings | Out-Null

    $authSettings = @{
        properties = @{
            platform = @{
                enabled = $true
                runtimeVersion = '~1'
            }
            globalValidation = @{
                requireAuthentication = $true
                unauthenticatedClientAction = 'Return401'
            }
            httpSettings = @{
                requireHttps = $true
            }
            login = @{
                tokenStore = @{
                    enabled = $false
                }
            }
            identityProviders = @{
                azureActiveDirectory = @{
                    enabled = $true
                    registration = @{
                        clientId = $apiApplication.AppId
                        clientSecretSettingName = 'MICROSOFT_PROVIDER_AUTHENTICATION_SECRET'
                        openIdIssuer = "https://login.microsoftonline.com/$tenantId/v2.0"
                    }
                    validation = @{
                        allowedAudiences = @("api://$($apiApplication.AppId)", $apiApplication.AppId)
                        defaultAuthorizationPolicy = @{
                            allowedApplications = @($nativeApplication.AppId)
                        }
                    }
                }
            }
        }
    } | ConvertTo-Json -Depth 12 -Compress

    $authSettingsUrl = "https://management.azure.com$($functionApp.id)/config/authsettingsV2?api-version=2022-09-01"
    & $az rest --method PUT --url $authSettingsUrl --body $authSettings | Out-Null

    $graphServicePrincipal = & $az rest --method GET --url "https://graph.microsoft.com/v1.0/servicePrincipals(appId='00000003-0000-0000-c000-000000000000')?%24select=id,appRoles" --output json | ConvertFrom-Json
    $graphRole = $graphServicePrincipal.appRoles | Where-Object {
        $_.value -eq 'GroupMember.Read.All' -and $_.allowedMemberTypes -contains 'Application'
    } | Select-Object -First 1
    if (-not $graphServicePrincipal.id -or -not $graphRole.id) {
        throw 'The Microsoft Graph application role GroupMember.Read.All was not found.'
    }

    $existingAssignments = & $az rest --method GET --url "https://graph.microsoft.com/v1.0/servicePrincipals/$($managedIdentity.principalId)/appRoleAssignments?%24select=id,resourceId,appRoleId" --output json | ConvertFrom-Json
    $existingGraphAssignment = $existingAssignments.value | Where-Object {
        $_.resourceId -eq $graphServicePrincipal.id -and $_.appRoleId -eq $graphRole.id
    } | Select-Object -First 1

    if (-not $existingGraphAssignment) {
        $assignment = @{
            principalId = $managedIdentity.principalId
            resourceId = $graphServicePrincipal.id
            appRoleId = $graphRole.id
        } | ConvertTo-Json -Compress
        & $az rest --method POST --url "https://graph.microsoft.com/v1.0/servicePrincipals/$($managedIdentity.principalId)/appRoleAssignments" --body $assignment | Out-Null
    }

    if ($PublishFunctionCode) {
        Require-Command dotnet
        $projectPath = Join-Path $PSScriptRoot '../../Backend/QuickElevate.Api/QuickElevate.Api.csproj'
        $publishPath = Join-Path $env:TEMP "quickelevate-function-$([guid]::NewGuid().ToString('N'))"
        $zipPath = "$publishPath.zip"

        dotnet publish $projectPath --configuration Release --output $publishPath
        Compress-Archive -Path "$publishPath/*" -DestinationPath $zipPath -Force
        & $az functionapp deployment source config-zip --resource-group $ResourceGroupName --name $FunctionAppName --src $zipPath | Out-Null
        Remove-Item $publishPath, $zipPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    [pscustomobject]@{
        TenantId = $tenantId
        FunctionAppName = $FunctionAppName
        ApiBaseUrl = "https://$FunctionAppName.azurewebsites.net"
        ApiApplicationId = $apiApplication.AppId
        NativeClientId = $nativeApplication.AppId
        ApiScope = "api://$($apiApplication.AppId)/$scopeName"
        ManagedIdentityPrincipalId = $managedIdentity.principalId
        ManagedIdentityClientId = $managedIdentity.clientId
        NextStep = 'Configure VPN/GSA routing and private DNS, then publish Function code if -PublishFunctionCode was not used.'
    } | Format-List
}
finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
}
