targetScope = 'resourceGroup'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Short lowercase environment suffix, for example dev, test, or prod.')
@minLength(2)
@maxLength(12)
param environmentName string

@description('Existing subnet resource ID used for the Function App inbound private endpoint.')
param privateEndpointSubnetId string

@description('Microsoft Entra tenant ID that can call the API.')
param tenantId string

@description('Immutable object ID of the PIM-managed Entra security group checked by the backend.')
param pimGroupObjectId string

@allowed([
  'Direct'
  'Transitive'
])
@description('Direct requires direct group membership. Transitive accepts nested group membership.')
param membershipMode string = 'Transitive'

@minValue(5)
@maxValue(300)
param defaultElevationSeconds int = 60

@minValue(5)
@maxValue(3600)
param maximumElevationSeconds int = 300

@description('Client ID of the Entra registration representing the native macOS app. Set after registering the client app.')
param nativeClientId string

@description('API application/client ID used as the Entra token audience.')
param apiApplicationId string

@description('A globally unique Function App name.')
param functionAppName string = 'func-quickelevate-${environmentName}-${uniqueString(resourceGroup().id)}'

var normalizedEnvironment = toLower(environmentName)
var storageName = toLower('stqe${uniqueString(resourceGroup().id, environmentName)}')
var keyVaultName = toLower('kv-qe-${normalizedEnvironment}-${uniqueString(resourceGroup().id)}')
var appInsightsName = 'appi-quickelevate-${normalizedEnvironment}'
var privateDnsZoneName = 'privatelink.azurewebsites.net'
var signingKeyName = 'elevation-grant'

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    DisableLocalAuth: true
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: tenantId
    enableRbacAuthorization: true
    enablePurgeProtection: true
    enableSoftDelete: true
    publicNetworkAccess: 'Enabled'
    sku: {
      family: 'A'
      name: 'standard'
    }
  }
}

resource signingKey 'Microsoft.KeyVault/vaults/keys@2023-07-01' = {
  parent: keyVault
  name: signingKeyName
  properties: {
    kty: 'RSA'
    keySize: 2048
    keyOps: [
      'sign'
      'verify'
    ]
    attributes: {
      enabled: true
    }
  }
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: privateDnsZoneName
  location: 'global'
}

resource functionPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'plan-quickelevate-${normalizedEnvironment}'
  location: location
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: functionPlan.id
    httpsOnly: true
    publicNetworkAccess: 'Disabled'
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
    }
  }
}

resource functionSettings 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: functionApp
  name: 'appsettings'
  properties: {
    FUNCTIONS_EXTENSION_VERSION: '~4'
    FUNCTIONS_WORKER_RUNTIME: 'dotnet-isolated'
    TENANT_ID: tenantId
    PIM_GROUP_OBJECT_ID: pimGroupObjectId
    MEMBERSHIP_MODE: membershipMode
    DEFAULT_ELEVATION_SECONDS: string(defaultElevationSeconds)
    MAXIMUM_ELEVATION_SECONDS: string(maximumElevationSeconds)
    GRANT_ISSUER: 'https://${functionApp.properties.defaultHostName}'
    GRANT_AUDIENCE: 'com.quickelevate.helper'
    KEY_VAULT_SIGNING_KEY_ID: signingKey.properties.keyUriWithVersion
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsights.properties.ConnectionString
    QUICK_ELEVATE_NATIVE_CLIENT_ID: nativeClientId
    QUICK_ELEVATE_API_APPLICATION_ID: apiApplicationId
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${functionAppName}'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'quickelevate-api'
        properties: {
          privateLinkServiceId: functionApp.id
          groupIds: [
            'sites'
          ]
        }
      }
    ]
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'webapps'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

output apiBaseUrl string = 'https://${functionApp.properties.defaultHostName}'
output apiAudience string = 'api://${apiApplicationId}'
output privateEndpointId string = privateEndpoint.id
output managedIdentityPrincipalId string = functionApp.identity.principalId
output keyVaultSigningKeyId string = signingKey.properties.keyUriWithVersion
output requiredGraphPermission string = 'GroupMember.ReadBasic.All (application permission, tenant admin consent required)'
