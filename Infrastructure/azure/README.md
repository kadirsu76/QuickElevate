# QuickElevate Azure Infrastructure

Deploy with Bicep after creating the Entra API and native-client app registrations:

```bash
az deployment group create \
  --resource-group <resource-group> \
  --template-file main.bicep \
  --parameters @azuredeploy.parameters.json
```

The quick deployment form requests only `tenantId` and `groupObjectId`. It creates a dedicated `10.250.0.0/16` VNet and `10.250.1.0/24` Private Endpoint subnet. The required `groupObjectId` is the immutable Entra Object ID for the security group. The backend keeps it in Function App settings. It is never accepted from the macOS app.

The public repository has an ARM JSON copy in `azuredeploy.json`; the README **Deploy to Azure** button opens that file in the Azure portal. Keep `azuredeploy.json` synchronized with `main.bicep` after changes.

## Post-deploy tenant administration

1. Add Microsoft Graph `GroupMember.ReadBasic.All` as an **application** permission to the Function system-assigned Managed Identity.
2. Grant tenant admin consent.
3. Configure App Service Authentication/Easy Auth for the single-tenant API registration and allow only the native client ID.
4. Connect the output `quickElevateVnetId` and `privateEndpointSubnetId` to corporate GSA/VPN routing. Forward `privatelink.azurewebsites.net` through the corporate DNS path.
5. Confirm public access stays disabled and test from a non-VPN network.
6. Deploy the Function code through an approved deployment path that can reach the private Function SCM endpoint.

Use `grant-managed-identity-graph-permission.ps1` to grant the required Graph application permission. Pass the `managedIdentityPrincipalId` deployment output:

```powershell
./grant-managed-identity-graph-permission.ps1 -mi <managedIdentityPrincipalId>
```

The script requires the Microsoft Graph PowerShell SDK. The signed-in operator needs `Application.Read.All` and `AppRoleAssignment.ReadWrite.All` delegated scopes and a directory role allowed to grant application permissions, such as Cloud Application Administrator or Privileged Role Administrator.

`Key Vault` is initially public but uses Managed Identity/RBAC. Add a Key Vault Private Endpoint as a later hardened deployment option if policy requires every dependency to be private.
