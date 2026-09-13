# QuickElevate Azure Infrastructure

Deploy with Bicep after creating the Entra API and native-client app registrations:

```bash
az deployment group create \
  --resource-group <resource-group> \
  --template-file main.bicep \
  --parameters @azuredeploy.parameters.json
```

The quick deployment form requests only `securityGroupObjectId`. The Azure subscription tenant ID is derived automatically and is used for Key Vault and backend Entra validation. It creates a dedicated `10.250.0.0/16` VNet and `10.250.1.0/24` Private Endpoint subnet. The required `securityGroupObjectId` is the immutable Entra Object ID for the security group. The backend keeps it in Function App settings. It is never accepted from the macOS app.

The public repository has an ARM JSON copy in `azuredeploy.json`; the README **Deploy to Azure** button opens that file in the Azure portal. Keep `azuredeploy.json` synchronized with `main.bicep` after changes.

## Post-deploy bootstrap

Run this once from PowerShell using an Entra tenant administrator account. It configures the Entra API/native client registrations, API scope, tenant-wide delegated consent, Easy Auth, Function client settings, and Graph read permission for the Managed Identity:

```powershell
./setup-quickelevate.ps1 `
  -rg rg-wd-quickelevate-p01 `
  -app <functionAppName>
```

Use `-PublishFunctionCode` when the machine running the script has .NET 8, Azure CLI, and an approved network path to the Function deployment endpoint:

```powershell
./setup-quickelevate.ps1 -rg rg-wd-quickelevate-p01 -app <functionAppName> -PublishFunctionCode
```

The script requires Azure CLI, .NET 8 only for code publish, and the Microsoft Graph PowerShell SDK. The signed-in operator needs delegated Graph scopes `Application.ReadWrite.All`, `AppRoleAssignment.ReadWrite.All`, and `DelegatedPermissionGrant.ReadWrite.All`, together with a directory role allowed to create applications and grant consent, such as Cloud Application Administrator or Privileged Role Administrator.

The template creates Azure RBAC role assignments for the user-assigned identity. The deployment principal needs `Microsoft.Authorization/roleAssignments/write` on this resource group. `Owner`, `User Access Administrator`, or `Role Based Access Control Administrator` at resource-group scope is sufficient; subscription-level Contributor alone is not.

After bootstrap, only VPN/GSA routing/private DNS and Function code publishing remain. The script produces the API URL, API scope, and native client ID needed for the Intune managed configuration profile. The macOS client uses the native client only for Platform SSO silent token acquisition; it does not open an Entra login screen.

`Key Vault` is initially public but uses Managed Identity/RBAC. Add a Key Vault Private Endpoint as a later hardened deployment option if policy requires every dependency to be private.
