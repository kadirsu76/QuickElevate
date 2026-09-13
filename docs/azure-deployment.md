# Azure Deployment

## Scope

The **Deploy to Azure** button provisions Azure infrastructure. It does not deploy Function code, create Microsoft Entra app registrations, grant Microsoft Graph permissions, create Conditional Access policies, or configure a VPN/GSA product. Those steps need tenant-level approval and are intentionally separate.

The quick deployment creates a dedicated VNet (`10.250.0.0/16`) and Private Endpoint subnet (`10.250.1.0/24`). After deployment, connect that VNet to your GSA/VPN and private DNS design. The private endpoint subnet must not be reused as an App Service/Function outbound VNet integration subnet.

## Required Parameters

| Parameter | Purpose |
| --- | --- |
| `tenantId` | Microsoft Entra tenant ID. |
| `securityGroupObjectId` | Immutable Entra Object ID of the security group. |

`securityGroupObjectId` is mandatory. It stays in Function App configuration and is never received from the macOS client.

`membershipMode` can be `Direct` or `Transitive`. `Transitive` accepts nested group membership. This is less strict than direct PIM membership and should be selected deliberately.

## Resources Created

- Flex Consumption Function hosting plan and Function App
- System-assigned Managed Identity
- Function inbound Private Endpoint
- `privatelink.azurewebsites.net` private DNS zone, VNet link, and DNS zone group
- Standard Key Vault and a non-exportable RSA signing key
- Application Insights

The Function App is configured with `publicNetworkAccess=Disabled`. The deployment does not create a public fallback API path.

## Post-deployment Tenant Tasks

1. Deploy the Function code to the provisioned Function App from a private-capable CI runner or a network path that reaches the SCM endpoint.
2. Configure App Service Authentication/Easy Auth for the backend API app registration.
3. Require authentication, return HTTP `401` for unauthenticated API calls, restrict the API to the configured tenant, and allow only the native macOS client ID.
4. Grant the Function Managed Identity Microsoft Graph application permission `GroupMember.ReadBasic.All`.
5. Grant tenant admin consent for that application permission.
6. Give the Function Managed Identity Key Vault RBAC permission to sign with the generated key.
7. Configure VPN/GSA route and private DNS forwarding. See [VPN and Global Secure Access](vpn-gsa-setup.md).
8. Configure Conditional Access if the deployment requires compliant devices, MFA, or other Entra conditions.

No Graph write permission is required. Do not make the Managed Identity an owner or member of the target group.

The repository includes an idempotent Graph PowerShell helper for steps 4-5:

```powershell
./Infrastructure/azure/grant-managed-identity-graph-permission.ps1 -mi <managedIdentityPrincipalId>
```

## Validation

From a machine on the VNet/VPN/GSA path, the normal Function hostname must resolve through the private-link record. An unauthenticated API request should receive HTTP `401`. From outside the private network, the API must not be reachable.
