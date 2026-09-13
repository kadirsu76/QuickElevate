# v0.1 Alpha Release Plan

## Included now

- macOS Dock agent prototype with confirmation dialog, Touch ID/password authentication, notification, and countdown UI.
- Root helper prototype with local expiration/revoke behavior.
- .NET 8 Function authorization API skeleton.
- Bicep infrastructure definition with mandatory `securityGroupObjectId` parameter, Flex deployment storage, user-assigned Managed Identity, and inbound Function Private Endpoint.
- Intune profile templates and deployment documentation.

## Required before pilot

- Install .NET 8 SDK and Azure CLI/Bicep in CI; run backend build and Bicep validation.
- Create Entra API and native-client registrations; configure Easy Auth.
- Grant Managed Identity `GroupMember.Read.All` and tenant admin consent.
- Build the helper signed-grant verifier, nonce issuance, replay store, and local Entra-to-macOS account binding.
- Connect the app to the private API using PSSO/MSAL silent-only token acquisition. Do not add an interactive Entra login fallback.
- Validate the completed backend grant verifier with end-to-end Key Vault signed grants and remove any remaining legacy local grant compatibility paths.
- Replace the socket transport with authenticated XPC or launchd socket activation.
- Add unit and integration tests.
- Build universal app/helper binaries, Developer ID sign all code, notarize the final PKG.
- Validate GSA/VPN route and `privatelink.azurewebsites.net` DNS from a managed Mac.

## Required before production

- Key Vault private endpoint if organizational policy requires all dependencies to remain private.
- HA decision for Function hosting and replay-store durability.
- Audit forwarding, alert rules, operational runbook, and incident response approval.
- Security review and penetration test.
