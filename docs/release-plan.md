# v0.1 Alpha Release Plan

## Included now

- macOS Dock agent prototype with confirmation dialog, Touch ID/password authentication, notification, and countdown UI.
- Root helper prototype with local expiration/revoke behavior.
- .NET 8 Function authorization API skeleton.
- Bicep infrastructure definition with mandatory `groupObjectId` parameter and inbound Function Private Endpoint.
- Intune profile templates and deployment documentation.

## Required before pilot

- Install .NET 8 SDK and Azure CLI/Bicep in CI; run backend build and Bicep validation.
- Create Entra API and native-client registrations; configure Easy Auth.
- Grant Managed Identity `GroupMember.ReadBasic.All` and tenant admin consent.
- Build the helper signed-grant verifier, nonce issuance, replay store, and local Entra-to-macOS account binding.
- Remove the unconditional local `.grant(user, seconds)` helper operation.
- Replace the socket transport with authenticated XPC or launchd socket activation.
- Add unit and integration tests.
- Build universal app/helper binaries, Developer ID sign all code, notarize the final PKG.
- Validate GSA/VPN route and `privatelink.azurewebsites.net` DNS from a managed Mac.

## Required before production

- Key Vault private endpoint if organizational policy requires all dependencies to remain private.
- HA decision for Function hosting and replay-store durability.
- Audit forwarding, alert rules, operational runbook, and incident response approval.
- Security review and penetration test.
