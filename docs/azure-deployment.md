# Azure Deployment

## Scope

The **Deploy to Azure** button provisions Azure infrastructure. It does not deploy Function code, create Microsoft Entra app registrations, grant Microsoft Graph permissions, create Conditional Access policies, or configure a VPN/GSA product. Those steps need tenant-level approval and are intentionally separate.

The quick deployment creates a dedicated VNet (`10.250.0.0/16`) and Private Endpoint subnet (`10.250.1.0/24`). After deployment, connect that VNet to your GSA/VPN and private DNS design. The private endpoint subnet must not be reused as an App Service/Function outbound VNet integration subnet.

## Required Parameters

| Parameter | Purpose |
| --- | --- |
| `securityGroupObjectId` | Immutable Entra Object ID of the security group. |

`securityGroupObjectId` is mandatory. It stays in Function App configuration and is never received from the macOS client.

`membershipMode` can be `Direct` or `Transitive`. `Transitive` accepts nested group membership. This is less strict than direct PIM membership and should be selected deliberately.

## Resources Created

- Flex Consumption Function hosting plan and Function App
- User-assigned Managed Identity
- Function inbound Private Endpoint
- `privatelink.azurewebsites.net` private DNS zone, VNet link, and DNS zone group
- Standard Key Vault and a non-exportable RSA signing key
- Application Insights

The Azure subscription tenant ID is automatically used for Key Vault and the backend's `TENANT_ID` setting. The Function App is configured with `publicNetworkAccess=Disabled`. The deployment does not create a public fallback API path.

## Post-deployment Bootstrap

Run the repository bootstrap script once as a tenant administrator:

```powershell
./Infrastructure/azure/setup-quickelevate.ps1 `
  -rg rg-wd-quickelevate-p01 `
  -app <functionAppName>
```

The script creates/reuses the single-tenant backend API and native macOS app registrations, creates the `Elevation.Request` delegated scope, grants tenant-wide native-client consent, enables Easy Auth, writes the native/API configuration to the Function App, and grants the user-assigned Managed Identity `GroupMember.Read.All`.

No Graph write permission is granted to the Managed Identity. Do not make the Managed Identity an owner or member of the target group.

Use `-PublishFunctionCode` only from a machine that can reach the Function deployment endpoint through the approved private network path and has .NET 8 installed.

After the bootstrap, configure VPN/GSA route and private DNS forwarding. See [VPN and Global Secure Access](vpn-gsa-setup.md). Configure Conditional Access if the deployment requires compliant devices, MFA, or other Entra conditions.

The deployment itself creates Azure RBAC role assignments for the Function identity. The operator running the template needs `Microsoft.Authorization/roleAssignments/write` at resource-group scope. A resource-group scoped `Owner`, `User Access Administrator`, or `Role Based Access Control Administrator` assignment is sufficient.

The repository also includes a narrower idempotent Graph-only helper:

```powershell
./Infrastructure/azure/grant-managed-identity-graph-permission.ps1 -mi <managedIdentityPrincipalId>
```

## Validation

From a machine on the VNet/VPN/GSA path, the normal Function hostname must resolve through the private-link record. An unauthenticated API request should receive HTTP `401`. From outside the private network, the API must not be reachable.

## Temporary Operator Access Before VPN/GSA

Until the private route and DNS path is ready, use the temporary operator script to allow only a known public egress IP. This is an App Service access restriction, not an NSG rule. An NSG cannot protect the App Service public frontend.

```powershell
./Infrastructure/azure/set-temporary-public-access.ps1 `
  -rg rg-wd-quickelevate-p01 `
  -app func-quickelevate-surygmpiizedm `
  -AllowedIp 188.119.54.129/32
```

The script enables Function App public ingress but adds allow rules for the supplied IP on both the API and SCM deployment endpoint, with `Deny` as the default action. Easy Auth continues to require a valid Entra token.

Disable the temporary public path immediately after VPN/GSA is functional:

```powershell
./Infrastructure/azure/set-temporary-public-access.ps1 `
  -rg rg-wd-quickelevate-p01 `
  -app func-quickelevate-surygmpiizedm `
  -Disable
```
