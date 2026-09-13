# Intune Deployment

## Prerequisites

- The Azure authorization API is deployed and reachable through the approved VPN/GSA path.
- `privatelink.azurewebsites.net` resolves from managed Macs while connected to the approved network.
- The Entra native-client registration and API registration are configured.
- The package is Developer ID signed and notarized before production deployment.

## Deployment Order

1. Deploy the corporate VPN/GSA client, route, and private-DNS policy.
2. Deploy the QuickElevate Service Management/background-item policy.
3. Deploy `deploy/QuickElevate-Configuration.mobileconfig.example`, completed with Azure deployment outputs.
4. Deploy `deploy/QuickElevate-Dock.mobileconfig` and `deploy/QuickElevate-Notifications.mobileconfig`.
5. Deploy the signed and notarized QuickElevate PKG as a required macOS PKG app.

The configuration profile should contain these deployment outputs:

| Managed setting | Source |
| --- | --- |
| `TenantId` | Entra tenant ID |
| `NativeClientId` | macOS native app registration client ID |
| `ApiAudience` | `api://<backend-api-application-id>` |
| `ApiBaseUrl` | `https://<function-app-name>.azurewebsites.net` |
| `RequestTimeoutSeconds` | `15` for the initial pilot |
| `MaximumElevationSeconds` | Backend policy ceiling, for example `300` |

Do not add `securityGroupObjectId` to the macOS profile. It belongs only on the backend.

Use `QuickElevate-Configuration.mobileconfig.example` only as a template. Replace every `<...>` value, generate new profile UUIDs, then upload it as a custom macOS profile.

Do not put Function keys, client secrets, Graph tokens, Key Vault credentials, or signing material in Intune scripts or profiles. The settings profile contains identifiers and URLs only.

The Intune post-install script is not the long-term settings channel. Use managed preferences so policy changes do not require a package reinstall.

## Assignment

- Assign VPN/GSA and DNS prerequisites before QuickElevate.
- Assign the app and configuration profiles to the same pilot device group.
- Use the Dock profile only when no other Dock payload is assigned to the same user/device. macOS accepts only one Dock payload.
- Start with a small pilot ring. Verify backend-denied users never receive local elevation.
