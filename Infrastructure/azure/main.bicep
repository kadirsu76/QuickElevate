targetScope = 'resourceGroup'

@description('Microsoft Entra tenant ID allowed to call the authorization API.')
param tenantId string

@description('Immutable object ID of the PIM-managed Entra security group checked by the backend.')
param pimGroupObjectId string

var location = resourceGroup().location
var suffix = toLower(uniqueString(resourceGroup().id))
var environmentName = 'prod'
var functionAppName = 'func-quickelevate-${suffix}'
var storageName = 'stqe${suffix}'
var keyVaultName = 'kvqe${suffix}'
var appInsightsName = 'appi-quickelevate-${suffix}'
var vnetName = 'vnet-quickelevate-${environmentName}'
var privateEndpointSubnetName = 'snet-private-endpoints'
var privateDnsZoneName = 'privatelink.azurewebsites.net'

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.250.0.0/16'
      ]
    }
    subnets: [
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: '10.250.1.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
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
  name: 'elevation-grant'
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

resource privateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZone
  name: 'quickelevate-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource functionPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'plan-quickelevate-${environmentName}'
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
    MEMBERSHIP_MODE: 'Transitive'
    DEFAULT_ELEVATION_SECONDS: '60'
    MAXIMUM_ELEVATION_SECONDS: '300'
    GRANT_ISSUER: 'https://${functionApp.properties.defaultHostName}'
    GRANT_AUDIENCE: 'com.quickelevate.helper'
    KEY_VAULT_SIGNING_KEY_ID: signingKey.properties.keyUriWithVersion
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsights.properties.ConnectionString
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${functionAppName}'
  location: location
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, privateEndpointSubnetName)
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
output functionAppName string = functionApp.name
output quickElevateVnetId string = vnet.id
output privateEndpointSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, privateEndpointSubnetName)
output managedIdentityPrincipalId string = functionApp.identity.principalId
output keyVaultSigningKeyId string = signingKey.properties.keyUriWithVersion
output requiredGraphPermission string = 'GroupMember.ReadBasic.All (application permission, tenant admin consent required)'
