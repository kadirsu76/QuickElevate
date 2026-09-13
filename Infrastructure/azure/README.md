# QuickElevate Azure Infrastructure

Deploy with Bicep after creating the Entra API and native-client app registrations:

```bash
az deployment group create \
  --resource-group <resource-group> \
  --template-file main.bicep \
  --parameters @azuredeploy.parameters.json
```

The required `pimGroupObjectId` is the immutable Entra Object ID for the PIM-managed security group. The backend keeps it in Function App settings. It is never accepted from the macOS app.

The public repository has an ARM JSON copy in `azuredeploy.json`; the README **Deploy to Azure** button opens that file in the Azure portal. Keep `azuredeploy.json` synchronized with `main.bicep` after changes.

## Post-deploy tenant administration

1. Add Microsoft Graph `GroupMember.ReadBasic.All` as an **application** permission to the Function system-assigned Managed Identity.
2. Grant tenant admin consent.
3. Configure App Service Authentication/Easy Auth for the single-tenant API registration and allow only the native client ID.
4. Connect the `privatelink.azurewebsites.net` private zone to corporate DNS through GSA/VPN routing and DNS forwarding.
5. Confirm public access stays disabled and test from a non-VPN network.
6. Deploy the Function code through an approved deployment path that can reach the private Function SCM endpoint.

`Key Vault` is initially public but uses Managed Identity/RBAC. Add a Key Vault Private Endpoint as a later hardened deployment option if policy requires every dependency to be private.
