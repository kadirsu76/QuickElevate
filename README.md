# QuickElevate

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fkadirsu76%2FQuickElevate%2Fmain%2FInfrastructure%2Fazure%2Fazuredeploy.json)

QuickElevate is a macOS just-in-time local administrator elevation project. A user requests a short elevation from a Dock-based app, authenticates with Touch ID or their local password, and receives local administrator membership for the policy-approved period.

The target production design requires an authorization decision from a private Azure Function before the root helper can elevate a user:

```text
QuickElevate macOS app
  -> Corporate VPN or Global Secure Access
  -> Azure Function Private Endpoint
  -> Microsoft Entra authentication and security group membership check
  -> Short-lived signed elevation grant
  -> Local root helper
  -> Temporary local administrator membership
```

## Status

> **Alpha. Not production-ready.** The current macOS helper still includes the original local-only grant flow. Do not deploy the current package to users until the backend-signed grant, nonce, replay protection, local identity binding, Developer ID signing, notarization, and automated test work are completed.

## Design Goals

- Use a private Azure backend reachable only through a corporate VPN, Global Secure Access, or any other network path that can route private traffic and resolve private DNS.
- Keep the backend off the public internet with an Azure Private Endpoint and disabled public network access.
- Authenticate the requesting user with Microsoft Entra ID.
- Check the user against one configured Entra security group.
- Support either direct or transitive group membership. `Transitive` is the default deployment option.
- Return an asymmetric, short-lived, single-use signed grant rather than an untrusted `allowed: true` response.
- Let only the local root helper validate and redeem the grant.
- Preserve the Dock lock state, countdown badge, confirmation dialog, Touch ID/password step, and user notifications.

## Deploy to Azure

Select **Deploy to Azure** above. The template creates the Azure infrastructure required for the pilot architecture:

- Azure Function Flex Consumption plan and Function App
- User-assigned Managed Identity
- Inbound Private Endpoint for the Function App
- `privatelink.azurewebsites.net` private DNS zone and endpoint DNS zone group
- Key Vault and an RSA signing key
- Application Insights
- Function settings, including the required security group object ID

The form requires only this value:

| Parameter | Description |
| --- | --- |
| `securityGroupObjectId` | Immutable object ID of the Entra security group. |

The template automatically uses the Azure subscription tenant and creates its own VNet, private endpoint subnet, Function App, stable user-assigned Managed Identity, storage account/deployment container, Key Vault/RSA signing key, Application Insights instance, private endpoint, and private DNS zone. The Function App is created with `publicNetworkAccess=Disabled`.

After deployment, connect the output `quickElevateVnetId` to your GSA/VPN/private-DNS design. This keeps the quick form simple while allowing any supported corporate VPN product to reach the new private endpoint.

The template does not create or grant Microsoft Entra tenant permissions. Complete the post-deployment steps in [Azure deployment](docs/azure-deployment.md).

## macOS Components

| Component | Responsibility |
| --- | --- |
| `QuickElevateApp` | Dock behavior, confirmation dialog, Touch ID/password authentication, backend request, notifications, and countdown state. |
| `QuickElevateHelper` | Root LaunchDaemon that is the only process allowed to change local `admin` membership and enforce expiry. |
| `QuickElevateShared` | Local IPC message contracts and transport code. |

## Development Build

```bash
swift build
swift build -c release
```

The backend is a .NET 8 isolated Azure Function in `Backend/QuickElevate.Api`. Install the .NET 8 SDK and Azure Functions Core Tools before building or running it locally.

```bash
dotnet build Backend/QuickElevate.Api/QuickElevate.Api.csproj
```

## macOS Packaging

```bash
chmod +x deploy/build-pkg.sh deploy/notarize-pkg.sh
swift build -c release
./deploy/build-pkg.sh 0.1.0
```

The current package is an alpha artifact. Production packaging must create universal binaries, sign the app and helper with a Developer ID Application certificate, sign the installer with a Developer ID Installer certificate, notarize the final package, and staple the notarization ticket.

## Intune Deployment

1. Deploy VPN/GSA routing and private DNS first.
2. Deploy the QuickElevate managed configuration profile.
3. Deploy Dock and notification profiles.
4. Deploy the signed/notarized PKG as a required macOS PKG app.

The profile templates and detailed instructions are in [deploy](deploy/) and [Intune deployment](docs/intune-deployment.md).

## Documentation

- [Architecture](docs/architecture.md)
- [Threat model](docs/threat-model.md)
- [Azure deployment](docs/azure-deployment.md)
- [VPN and Global Secure Access](docs/vpn-gsa-setup.md)
- [Intune deployment](docs/intune-deployment.md)
- [Alpha release plan](docs/release-plan.md)
- [Security reporting](SECURITY.md)

## Security Model

Temporary membership in the macOS `admin` group is broad local administrator access, not per-process elevation. Removing the membership at expiry does not undo durable changes made while elevated. Keep elevation windows short, require the Azure/PIM authorization gate, harden and monitor endpoints, and retain an independent recovery path.
